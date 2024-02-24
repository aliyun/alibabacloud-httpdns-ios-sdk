#!/bin/bash

# capture ERR signal
trap 'echo "An error occurred. Exiting..." && exit 2' ERR

BUILD_CONFIG="Release" # Default configuration

if [[ $# -gt 0 ]]; then
  case "$1" in
    debug)
      BUILD_CONFIG="Debug"
      ;;
    release)
      BUILD_CONFIG="Release"
      ;;
    *)
      echo "Usage: $0 [debug/release(default)]"
      exit 1
      ;;
  esac
fi

echo "Building configuration '$BUILD_CONFIG'"

FRAMEWORK_NAME='AlicloudHttpDNS'
FRAMEWORK_VERSION=1.0
FRAMEWORK_CONFIG="$BUILD_CONFIG"
PRODUCT_DIR="Products"
XCFRAMEWORK_PATH="${PRODUCT_DIR}/${FRAMEWORK_NAME}.xcframework"

# Ensure PRODUCT_DIR is clean
rm -rf "$PRODUCT_DIR"
mkdir -p "$PRODUCT_DIR"

build_framework() {
  sdk="$1"
  archs=("${@:2}") # Pass in remaining arguments as array
  arch_flags="${archs[@]/#/-arch }" # Prefix each arch with "-arch"

  xcodebuild build -configuration "$FRAMEWORK_CONFIG" -scheme "$FRAMEWORK_NAME" -sdk "$sdk" $arch_flags

  # Directly use the output of xcodebuild -showBuildSettings to avoid re-execution and errors
  local build_settings
  build_settings="$(xcodebuild -configuration "$FRAMEWORK_CONFIG" -sdk "$sdk" -arch "${archs[0]}" -showBuildSettings)"
  local built_products_dir
  built_products_dir=$(echo "$build_settings" | grep " BUILT_PRODUCTS_DIR =" | sed "s/.*= //")

  eval "FRAMEWORK_PATH_${sdk}='${built_products_dir}/${FRAMEWORK_NAME}.framework'"
}

build_framework iphoneos arm64
build_framework iphonesimulator x86_64 arm64

DEVICE_FRAMEWORK=$(eval echo \$FRAMEWORK_PATH_iphoneos)
SIMULATOR_FRAMEWORK=$(eval echo \$FRAMEWORK_PATH_iphonesimulator)

# Create xcframework
xcodebuild -create-xcframework -framework "$DEVICE_FRAMEWORK" -framework "$SIMULATOR_FRAMEWORK" -output "$XCFRAMEWORK_PATH"

# Remove _CodeSignature directories
echo "Removing _CodeSignature directories."
find "$XCFRAMEWORK_PATH" -name '_CodeSignature' -type d -exec rm -rf {} +

echo -e "\nBUILD FINISH."
