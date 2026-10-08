Pod::Spec.new do |s|
  s.name             = 'fresh_builder_viewport_texture'
  s.version          = '0.1.0'
  s.summary          = 'Native Flutter texture bridge for Fresh Builder viewport frames.'
  s.description      = <<-DESC
Native Flutter texture bridge for Fresh Builder viewport frames.
                       DESC
  s.homepage         = 'https://freshstl.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'FreshSTL' => 'support@freshstl.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.static_framework = true
end
