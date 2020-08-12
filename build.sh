#!/bin/sh

PROJECT_NAME='AlicloudHttpDNS'
SRCROOT='.'

# Sets the target folders and the final framework product.
# 如果工程名称和Framework的Target名称不一样的话，要自定义FMKNAME
# 例如: FMK_NAME = "MyFramework"
FMK_NAME=${PROJECT_NAME}

# Install dir will be the final output to the framework.
# The following line create it in the root folder of the current project.
INSTALL_DIR=${SRCROOT}/Products/${PROJECT_NAME}.framework

# Working dir will be deleted after the framework creation.
WRK_DIR=build
DEVICE_DIR=${WRK_DIR}/Release-iphoneos/${FMK_NAME}.framework
SIMULATOR_DIR=${WRK_DIR}/Release-iphonesimulator/${FMK_NAME}.framework

# -configuration ${CONFIGURATION}
# Clean and Building both architectures.
xcodebuild -configuration "Release" -target "${FMK_NAME}" -sdk iphoneos build
xcodebuild -configuration "Release" -target "${FMK_NAME}" -sdk iphonesimulator build

# Cleaning the oldest.
if [ -d "${INSTALL_DIR}" ]
then
    rm -rf "${INSTALL_DIR}"
fi

mkdir -p "${INSTALL_DIR}"

cp -r "${DEVICE_DIR}" ${SRCROOT}/Products/

# Uses the Lipo Tool to merge both binary files (i386 + armv6/armv7) into one Universal final product.
lipo -create "${DEVICE_DIR}/${FMK_NAME}" "${SIMULATOR_DIR}/${FMK_NAME}" -output "${INSTALL_DIR}/${FMK_NAME}"

rm -r "${WRK_DIR}"

if [ -d "${INSTALL_DIR}/_CodeSignature" ]
then
    rm -rf "${INSTALL_DIR}/_CodeSignature"
fi

if [ -f "${INSTALL_DIR}/Info.plist" ]
then
    rm "${INSTALL_DIR}/Info.plist"
fi

if [ -d "${INSTALL_DIR}/ALBB.bundle" ]
then
    rm -rf "${INSTALL_DIR}/ALBB.bundle"
fi

# 压缩zip
cd "Products"
echo "zip  begin......."
zip -r "httpdns.zip" "${PROJECT_NAME}.framework"
echo "zip  end......."

echo "\nBUILD FINISH."