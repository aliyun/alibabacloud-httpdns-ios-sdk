#!/bin/bash

set -x

FRAMEWORK_ID="httpdns"
FRAMEWORK_NAME="AlicloudHttpDNS"
BUILD_CONFIG="release"
BUILD_DIR="`pwd`/Build"

# remove and make Build directory
rm -rf Build && mkdir Build

# clone git@gitlab.alibaba-inc.com:alicloud-ams/ios-xcframework-build-script.git to Build directory
git clone git@gitlab.alibaba-inc.com:alicloud-ams/ios-xcframework-build-script.git Build/ios-xcframework-build-script

sh Build/ios-xcframework-build-script/build.sh $FRAMEWORK_ID $FRAMEWORK_NAME $BUILD_CONFIG $BUILD_DIR
