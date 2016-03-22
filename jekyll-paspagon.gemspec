require 'English'

Gem::Specification.new do |s|
  s.name = 'jekyll-paspagon'
  s.version = '1.0.2'
  s.author = 'Krzysztof Jurewicz'
  s.email = 'krzysztof.jurewicz@gmail.com'
  s.summary = 'Sell your Jekyll posts'
  s.description = 'Sell your Jekyll posts in various formats for cryptocurrencies'
  s.homepage = 'https://github.com/KrzysiekJ/jekyll-paspagon'
  s.license = 'MIT'

  s.files = `git ls-files`.split($INPUT_RECORD_SEPARATOR).grep(%r{^lib/})
  s.extra_rdoc_files = ['README.md', 'LICENSE']

  s.add_runtime_dependency 'ffi-xattr', '~> 0.1', '>= 0.1.2'
  s.add_runtime_dependency 'aws-sdk', '~> 2'

  s.add_development_dependency 'rubocop', '~> 0.38', '>= 0.38.0'
end
