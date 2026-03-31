#!/bin/bash

# 打印信息函数
print_info() {
  echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
  echo -e "\033[31m[ERROR]\033[0m $1"
}

print_warning() {
  echo -e "\033[33m[WARNING]\033[0m $1"
}

# check parameters, usage: ./build_proj.sh framework_id framework_name build_config build_dir [project_name]
if [ $# -lt 4 ]; then
  echo "Usage: $0 framework_id framework_name build_config build_dir [project_name]"
  echo ""
  echo "Parameters:"
  echo "  framework_id    - Framework的唯一标识符"
  echo "  framework_name  - Framework的名称"
  echo "  build_config    - 构建配置 (Debug/Release)"
  echo "  build_dir       - 构建输出目录"
  echo "  project_name    - Project名称 (可选，默认使用framework_name)"
  exit 1
fi

print_info "开始构建 XCFramework (Project 模式)..."
print_info "构建参数: $@"

FRAMEWORK_ID=$1
FRAMEWORK_NAME=$2
BUILD_CONFIG=$3
BUILD_DIR=$4
PROJECT_NAME=${5:-$FRAMEWORK_NAME}  # 如果没有提供project_name，则使用framework_name

# if build_config is not specified, use release as default
if [ -z "$BUILD_CONFIG" ]; then
  BUILD_CONFIG="Release"
fi

print_info "构建配置: $BUILD_CONFIG"
print_info "Framework ID: $FRAMEWORK_ID"
print_info "Framework 名称: $FRAMEWORK_NAME"
print_info "Project 名称: $PROJECT_NAME"
print_info "构建目录: $BUILD_DIR"

build_framework() {
  sdk="$1"
  archs=("${@:2}") # Pass in remaining arguments as array
  arch_flags="${archs[@]/#/-arch }" # Prefix each arch with "-arch"

  print_info "构建 $sdk 平台，架构: ${archs[*]}"

  xcodebuild -project "${PROJECT_NAME}.xcodeproj" -configuration "$BUILD_CONFIG" -scheme "$FRAMEWORK_NAME" -sdk "$sdk" $arch_flags build

  if [ $? -ne 0 ]; then
    print_error "$sdk 平台构建失败!"
    exit 1
  fi

  # Directly use the output of xcodebuild -showBuildSettings to avoid re-execution and errors
  local build_settings
  local built_products_dir

  build_settings="$(xcodebuild -project "${PROJECT_NAME}.xcodeproj" -configuration "$BUILD_CONFIG" -scheme "$FRAMEWORK_NAME" -sdk "$sdk" $arch_flags -showBuildSettings)"
  built_products_dir=$(echo "$build_settings" | grep " BUILT_PRODUCTS_DIR =" | sed "s/.*= //")
  print_info "构建产物目录: ${built_products_dir}"

  eval "FRAMEWORK_PATH_${sdk}='${built_products_dir}/${FRAMEWORK_NAME}.framework'"
}

build_framework iphoneos arm64
build_framework iphonesimulator x86_64 arm64

DEVICE_FRAMEWORK=$(eval echo \$FRAMEWORK_PATH_iphoneos)
SIMULATOR_FRAMEWORK=$(eval echo \$FRAMEWORK_PATH_iphonesimulator)

print_info "设备端 Framework 路径: $DEVICE_FRAMEWORK"
print_info "模拟器 Framework 路径: $SIMULATOR_FRAMEWORK"

cd "$BUILD_DIR"

mkdir -p ${FRAMEWORK_ID}

# Create xcframework
print_info "创建 XCFramework..."
xcodebuild -create-xcframework -framework "$DEVICE_FRAMEWORK" -framework "$SIMULATOR_FRAMEWORK" -output "${FRAMEWORK_ID}/${FRAMEWORK_NAME}.xcframework"

if [ $? -ne 0 ]; then
  print_error "XCFramework 创建失败!"
  exit 1
fi

# Remove _CodeSignature directories
print_info "清理代码签名目录..."
find "${FRAMEWORK_ID}/${FRAMEWORK_NAME}.xcframework" -name '_CodeSignature' -type d -exec rm -rf {} +

print_info "打包 ZIP 文件..."
zip -r ${FRAMEWORK_ID}.zip ${FRAMEWORK_ID}

if [ $? -eq 0 ]; then
  print_info "✅ 构建完成!"
  print_info "📦 输出文件: ${BUILD_DIR}/${FRAMEWORK_ID}.zip"
  print_info "📁 Framework 目录: ${BUILD_DIR}/${FRAMEWORK_ID}/${FRAMEWORK_NAME}.xcframework"
else
  print_error "ZIP 打包失败!"
  exit 1
fi
