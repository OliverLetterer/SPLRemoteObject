Pod::Spec.new do |spec|
  spec.name         = 'SPLRemoteObject'
  spec.version      = '2.0.0'
  spec.platform     = :ios, '7.0'
  spec.license      = 'MIT'
  spec.source       = { :git => 'https://github.com/OliverLetterer/SPLRemoteObject.git', :tag => spec.version.to_s }
  spec.frameworks   = 'Foundation', 'UIKit', 'CFNetwork', 'Security'
  spec.requires_arc = true
  spec.homepage     = 'https://github.com/OliverLetterer/SPLRemoteObject'
  spec.summary      = 'Its just an objc RPC framework for your local network.'
  spec.author       = { 'Oliver Letterer' => 'oliver.letterer@gmail.com' }
  spec.source_files = 'SPLRemoteObject'

  spec.dependency 'SLObjectiveCRuntimeAdditions', '>= 1.0.0'
end
