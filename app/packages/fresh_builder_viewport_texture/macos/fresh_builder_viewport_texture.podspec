Pod::Spec.new do |s|
  s.name             = 'fresh_builder_viewport_texture'
  s.version          = '0.1.0'
  s.summary          = 'Native Fresh Builder viewport texture bridge.'
  s.description      = <<-DESC
Native Flutter texture presentation for Fresh Builder WGPU frames.
                       DESC
  s.homepage         = 'https://freshstl.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'FreshSTL' => 'support@freshstl.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
  s.frameworks = 'CoreVideo'
end
