Pod::Spec.new do |s|
  s.name = 'CoreDataOperation'
  s.version = '1.0.0'
  s.license = 'MIT'
  s.summary = 'CoreDataOperation is a fast, safe, flexible class for updating your data model.'
  s.homepage = 'https://github.com/Adlai-Holler/CoreDataOperation'
  s.social_media_url = 'http://twitter.com/adlaih'
  s.authors = { 'Adlai Holler' => 'him@adlai.io' }
  s.source = { :git => 'https://github.com/Adlai-Holler/CoreDataOperation.git', :tag => 'v1.0.0' }

  s.ios.deployment_target = '8.0'
  
  s.source_files = 'CoreDataOperation/*.swift'

  s.requires_arc = true
end
