source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/aliyun/aliyun-specs.git'

use_frameworks!

platform :ios, '12.0'

target 'AlicloudHttpDNS' do

  pod 'AlicloudUtils', '1.4.1-private'
  pod 'AlicloudUTDID', '1.5.0.95-private'

end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
        end
    end
end
