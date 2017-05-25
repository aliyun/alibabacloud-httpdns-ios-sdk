Pod::Spec.new do |s|

  s.name         = "AlicloudHTTPDNS"
  s.version      = "1.6.0"
  s.summary      = "Aliyun Mobile Service HTTPDNS iOS SDK."
  s.homepage     = "https://www.aliyun.com/product/httpdns?spm=5176.8142029.388261.87.WDYRC6"
  s.author       = { "junmo" => "lingkun.lk@alibaba-inc.com" }
  s.platform     = :ios
  s.source       = { :http => "framework_url" }
  s.vendored_frameworks = 'httpdns/AlicloudHttpDNS.framework'
  s.library = 'sqlite3.0'
  s.dependency "AlicloudUtils"

end
