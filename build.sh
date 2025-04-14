#!/bin/bash

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get NDK download URL based on OS
get_ndk_url() {
    local os=$1
    case "$os" in
        "macos")
            echo "https://dl.google.com/android/repository/android-ndk-r25c-darwin.dmg"
            ;;
        "linux")
            echo "https://dl.google.com/android/repository/android-ndk-r25c-linux.zip"
            ;;
        "windows")
            echo "https://dl.google.com/android/repository/android-ndk-r25c-windows.zip"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Download and install NDK
setup_ndk() {
    local os=$1
    local ndk_url=$(get_ndk_url "$os")
    local temp_dir=$(mktemp -d)
    local ndk_root=""

    echo "Setting up Android NDK r25c..."

    # Determine NDK installation path based on OS
    case "$os" in
        "macos")
            ndk_root="$HOME/Library/Android/sdk/ndk/25.2.9519653"
            ;;
        "linux")
            ndk_root="$HOME/Android/Sdk/ndk/25.2.9519653"
            ;;
        "windows")
            ndk_root="$LOCALAPPDATA/Android/sdk/ndk/25.2.9519653"
            ;;
        *)
            echo "Unsupported operating system"
            exit 1
            ;;
    esac

    # Check if NDK already exists
    if [ -d "$ndk_root" ]; then
        echo "NDK already installed at $ndk_root"
        export ANDROID_NDK_ROOT="$ndk_root"
        return 0
    fi

    echo "Downloading NDK from $ndk_url..."
    
    case "$os" in
        "macos")
            curl -L "$ndk_url" -o "$temp_dir/ndk.dmg"
            hdiutil attach "$temp_dir/ndk.dmg"
            mkdir -p "$ndk_root"
            cp -R "/Volumes/Android NDK r25c/AndroidNDK9519653.app/Contents/NDK/" "$ndk_root"
            hdiutil detach "/Volumes/Android NDK r25c"
            ;;
        "linux")
            wget -O "$temp_dir/ndk.zip" "$ndk_url"
            mkdir -p "$ndk_root"
            unzip -q "$temp_dir/ndk.zip" -d "$temp_dir"
            mv "$temp_dir/android-ndk-r25c"/* "$ndk_root/"
            ;;
        "windows")
            powershell -Command "Invoke-WebRequest -Uri $ndk_url -OutFile $temp_dir/ndk.zip"
            mkdir -p "$ndk_root"
            powershell -Command "Expand-Archive -Path $temp_dir/ndk.zip -DestinationPath $temp_dir"
            mv "$temp_dir/android-ndk-r25c"/* "$ndk_root/"
            ;;
    esac

    rm -rf "$temp_dir"
    export ANDROID_NDK_ROOT="$ndk_root"
    echo "NDK installed successfully at $ndk_root"
}

# Build for a specific architecture
build_arch() {
    local arch=$1
    echo "Building for $arch..."
    
    # Clean previous build
    rm -rf build/
    
    # Configure with all necessary options
    ./configure \
        --host="android-$arch" \
        --prefix="$(pwd)/build-output/$arch" \
        --disable-graft-tool \
        --disable-tests \
        --with-devkits=gum \
        --disable-quickjs \
        --disable-v8 \
        --disable-database \
        --disable-frida-objc-bridge \
        --disable-frida-swift-bridge \
        --disable-frida-java-bridge || {
            echo "Configuration failed for $arch"
            return 1
        }
    
    # Build with error checking
    make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4) || {
        echo "Build failed for $arch"
        return 1
    }
    
    # Create output directory for this architecture
    mkdir -p "build-output/$arch"
    
    # Only copy the essential libraries and headers
    mkdir -p "build-output/$arch/lib"
    mkdir -p "build-output/$arch/include/frida-gum"
    
    # Copy from devkit
    cp build/gum/devkit/libfrida-gum.a "build-output/$arch/lib/" || {
        echo "Failed to copy library for $arch"
        return 1
    }
    
    cp build/gum/devkit/frida-gum.h "build-output/$arch/include/frida-gum/" || {
        echo "Failed to copy headers for $arch"
        return 1
    }
    
    echo "Successfully built for $arch"
}

# Main script
main() {
    local os=$(detect_os)
    echo "Detected OS: $os"

    # Clear previous build output
    echo "Cleaning previous build output..."
    rm -rf build-output/

    # Setup NDK
    setup_ndk "$os"

    if [ -z "$ANDROID_NDK_ROOT" ]; then
        echo "Error: ANDROID_NDK_ROOT is not set"
        exit 1
    fi

    # Create output directory
    mkdir -p build-output

    # Build for all architectures
    local architectures=("arm" "arm64" "x86" "x86_64")
    for arch in "${architectures[@]}"; do
        build_arch "$arch"
    done

    echo "Build completed successfully!"
    echo "Output files are in the build-output directory"
}

# Run the script
main 