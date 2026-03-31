# EMAS SDK 打包脚本

iOS XCFramework 构建脚本，支持 Workspace 和 Project 两种模式。

## 功能特性

- 🏗️ 支持 Workspace 和 Project 两种构建模式
- 📱 自动构建 iOS 设备端和模拟器端 Framework
- 🔄 自动创建通用 XCFramework
- 📦 自动打包为 ZIP 文件
- 🎯 支持自定义 Framework 名称和 Workspace/Project 名称
- ✅ 完整的错误处理和状态提示

## 脚本说明

### build.sh - Workspace 模式

适用于使用 `.xcworkspace` 文件的项目（通常包含 CocoaPods 依赖）

### build_proj.sh - Project 模式

适用于使用 `.xcodeproj` 文件的项目（纯原生项目）

## 使用方法

### 基本用法

```bash
# Workspace 模式
./build.sh framework_id framework_name build_config build_dir [workspace_name]

# Project 模式
./build_proj.sh framework_id framework_name build_config build_dir [project_name]
```

### 参数说明

| 参数             | 说明                                            | 示例                 |
| ---------------- | ----------------------------------------------- | -------------------- |
| `framework_id`   | Framework 的唯一标识符，用作输出目录名          | `MySDK_1.0.0`        |
| `framework_name` | Framework 的名称，对应 Scheme 名称              | `MySDK`              |
| `build_config`   | 构建配置                                        | `Debug` 或 `Release` |
| `build_dir`      | 构建输出目录的绝对路径                          | `/path/to/output`    |
| `workspace_name` | Workspace 名称（可选，默认使用 framework_name） | `MyProject`          |
| `project_name`   | Project 名称（可选，默认使用 framework_name）   | `MyProject`          |

### 使用示例

#### 示例 1：Framework 名称与 Workspace 名称相同

```bash
./build.sh MySDK_1.0.0 MySDK Release /Users/developer/output
```

#### 示例 2：Framework 名称与 Workspace 名称不同

```bash
./build.sh MySDK_1.0.0 MySDK Release /Users/developer/output MyProject
```

#### 示例 3：一个 Workspace 包含多个 SDK

```bash
# 构建第一个 SDK
./build.sh SDK1_1.0.0 SDK1 Release /Users/developer/output SharedWorkspace

# 构建第二个 SDK
./build.sh SDK2_1.0.0 SDK2 Release /Users/developer/output SharedWorkspace
```

#### 示例 4：Project 模式

```bash
./build_proj.sh MySDK_1.0.0 MySDK Release /Users/developer/output MyProject
```

## 输出结果

构建成功后，会在指定的 `build_dir` 目录下生成：

```
build_dir/
├── framework_id.zip                    # 打包的 ZIP 文件
└── framework_id/                       # Framework 目录
    └── framework_name.xcframework/     # XCFramework 文件
        ├── ios-arm64/                  # iOS 设备端
        └── ios-arm64_x86_64-simulator/ # iOS 模拟器端
```

## 构建流程

1. **参数验证** - 检查必需参数是否提供
2. **设备端构建** - 构建 iOS 设备端 Framework (arm64)
3. **模拟器端构建** - 构建 iOS 模拟器端 Framework (x86_64 + arm64)
4. **创建 XCFramework** - 合并设备端和模拟器端 Framework
5. **清理签名** - 移除 \_CodeSignature 目录
6. **打包** - 创建 ZIP 压缩包

## 注意事项

- 确保 Xcode 已正确安装并配置
- 确保项目的 Scheme 是 Shared 的
- 构建前请确保项目能够正常编译
- 输出目录会自动创建，无需手动创建
- 脚本会自动清理之前的构建产物

## 错误排查

### 常见问题

1. **Scheme 未找到**

   - 确保 Scheme 名称正确
   - 确保 Scheme 是 Shared 的

2. **构建失败**

   - 检查项目依赖是否正确安装
   - 确保代码能够正常编译

3. **权限问题**
   - 确保脚本有执行权限：`chmod +x build.sh`
   - 确保对输出目录有写权限

## 集成示例

可以将此脚本集成到 CI/CD 流程中：

```bash
#!/bin/bash

print_info() {
  echo -e "\033[32m[INFO]\033[0m $1"
}

print_error() {
  echo -e "\033[31m[ERROR]\033[0m $1"
}

# 设置构建参数
FRAMEWORK_ID="MySDK_$(date +%Y%m%d_%H%M%S)"
FRAMEWORK_NAME="MySDK"
BUILD_CONFIG="Release"
BUILD_DIR="/tmp/build"
WORKSPACE_NAME="MyProject"

print_info "开始构建 XCFramework..."

# 清理并创建构建目录
rm -rf Build && mkdir Build

# 执行构建（从项目根目录执行）
sh ios-xcframework-build-script/build.sh $FRAMEWORK_ID $FRAMEWORK_NAME $BUILD_CONFIG $BUILD_DIR $WORKSPACE_NAME

if [[ $? -eq 0 ]]; then
  print_info "$FRAMEWORK_NAME XCFramework 构建完成!"
  print_info "Framework ID: $FRAMEWORK_ID"
  print_info "构建目录: $BUILD_DIR"
else
  print_error "$FRAMEWORK_NAME XCFramework 构建失败!"
  exit 1
fi
```
