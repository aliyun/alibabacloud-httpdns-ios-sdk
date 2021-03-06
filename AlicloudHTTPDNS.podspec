Pod::Spec.new do |s|

  s.name         = "AlicloudHTTPDNS"
  s.version      = "1.19.2.8"
  s.summary      = "Aliyun Mobile Service HTTPDNS iOS SDK."
  s.homepage     = "https://www.aliyun.com/product/httpdns"
  s.author       = { "junmo" => "junmo" }
  s.platform     = :ios
  s.ios.deployment_target = '7.0'
  s.source       = { :http => "framework_url" }
  s.vendored_frameworks = 'httpdns/AlicloudHttpDNS.framework'
  s.source_files = 'AlicloudHttpDNS/*','AlicloudHttpDNS/**/*','AlicloudHttpDNS/**/**/*'
  s.library = 'sqlite3.0'
  s.xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -ObjC -lz' }
  s.dependency "AlicloudUtils"
  s.dependency "AlicloudUT"

end
