#!/bin/bash

set -x

FRAMEWORK_ID="httpdns"
FRAMEWORK_NAME="AlicloudHttpDNS"
BUILD_CONFIG="release"
BUILD_DIR="`pwd`/Build"

# remove and make Build directory
rm -rf Build && mkdir Build

# 直接调用本地构建脚本
sh ios-xcframework-build-script/build.sh $FRAMEWORK_ID $FRAMEWORK_NAME $BUILD_CONFIG $BUILD_DIR
