lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'simple_scrobbler/version'

Gem::Specification.new do |s|
  s.name        = "simple_scrobbler"
  s.version     = SimpleScrobbler::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Paul Battley"]
  s.email       = ["pbattley@gmail.com"]
  s.homepage    = "http://github.com/threedaymonk/simple_scrobbler"
  s.summary     = "A simple Last.fm scrobbler that works"
  s.description = "Scrobble tracks to Last.fm without wanting to gnaw your own arm off."

  s.add_development_dependency "mocha"
  s.add_development_dependency "fakeweb"

  s.files        = Dir["{bin,lib}/**/*"] + %w[README.md]
  s.require_path = 'lib'
end
