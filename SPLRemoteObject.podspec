Pod::Spec.new do |spec|
  spec.name         = 'SPLRemoteObject'
  spec.version      = '2.0.14'
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
  spec.prefix_header_contents = '#ifndef NS_BLOCK_ASSERTIONS', '#define __assert_unused', '#else', '#define __assert_unused __unused', '#endif'
end
