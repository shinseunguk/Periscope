Pod::Spec.new do |spec|
  spec.name         = "Periscope"
  spec.version      = "1.0.0"
  spec.summary      = "A Swift library for Periscope functionality"
  spec.description  = <<-DESC
                      Periscope is a Swift library that provides awesome functionality
                      for your iOS, macOS, tvOS, and watchOS applications.
                      DESC
  spec.homepage     = "https://github.com/shinseunguk/Periscope"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "shinseunguk" => "krdut1@gmail.com" }
  
  spec.ios.deployment_target = "13.0"
  spec.osx.deployment_target = "10.15"
  spec.tvos.deployment_target = "13.0"
  spec.watchos.deployment_target = "6.0"
  
  spec.source       = { :git => "https://github.com/shinseunguk/Periscope.git", :tag => "#{spec.version}" }
  spec.source_files = "Periscope/**/*.swift"
  spec.swift_version = "5.7"
  
  # spec.dependency "JSONKit", "~> 1.4"
end