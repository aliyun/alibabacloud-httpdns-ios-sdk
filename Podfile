source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/aliyun/aliyun-specs.git'

use_frameworks!

platform :ios, '10.0'

def shared_pods
  pod 'AlicloudUtils', '2.0.1'
end

target 'AlicloudHttpDNS' do
  shared_pods
end

target 'AlicloudHttpDNSTestDemo' do
  shared_pods
end

target 'AlicloudHttpDNSTests' do
  shared_pods
  pod 'OCMock', '3.9.3'
end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '10.0'
        end
    end
end
