Pod::Spec.new do |spec|
  spec.name         = 'SPLRemoteObject'
  spec.version      = '2.0.6'
  spec.platform     = :ios, '7.0'
  spec.license      = 'MIT'
  spec.source       = { :git => 'https://github.com/OliverLetterer/SPLRemoteObject.git', :tag => spec.version.to_s }
  spec.frameworks   = 'Foundation', 'UIKit', 'CFNetwork', 'Security'
  spec.requires_arc = true
  spec.homepage     = 'https://github.com/OliverLetterer/SPLRemoteObject'
  spec.summary      = 'Major rewrite of SLRemoteObject.'
  spec.author       = { 'Oliver Letterer' => 'oliver.letterer@gmail.com' }
  spec.source_files = 'SPLRemoteObject'

  spec.dependency 'SLObjectiveCRuntimeAdditions', '>= 1.0.0'
end
