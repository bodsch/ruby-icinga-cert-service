
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cert-service/version'

Gem::Specification.new do |s|

  s.name        = 'icinga-cert-service'
  s.version     = IcingaCertService::VERSION
  s.date        = '2020-03-20'
  s.summary     = 'Icinga Certificate Service'
  s.description = 'Ruby Class to create an provide a Icinga2 Certificate for Satellites or Agents '
  s.authors     = ['Bodo Schulz']
  s.email       = 'bodo@boone-schulz.de'

  s.files       = Dir[
    'README.md',
    'LICENSE',
    'lib/**/*',
    'bin/*',
    'doc/*.md',
    'examples/*.rb'
  ]

  s.homepage    = 'https://github.com/bodsch/ruby-icinga-cert-service'
  s.license     = 'LGPL-2.1+'

  begin
    if( RUBY_VERSION >= '2.0' )
      s.required_ruby_version = '~> 2.0'
    elsif( RUBY_VERSION <= '2.1' )
      s.required_ruby_version = '~> 2.1'
    elsif( RUBY_VERSION <= '2.2' )
      s.required_ruby_version = '~> 2.2'
    elsif( RUBY_VERSION <= '2.3' )
      s.required_ruby_version = '~> 2.3'
    elsif( RUBY_VERSION <= '2.4' )
      s.required_ruby_version = '~> 2.4'
    elsif( RUBY_VERSION <= '2.5' )
      s.required_ruby_version = '~> 2.5'
    end

    s.add_dependency('etc', '~> 1.1')     if RUBY_VERSION =~ /^2.5/
    s.add_dependency('ruby_dig', '~> 0')  if RUBY_VERSION < '2.3'
    s.add_dependency('openssl', '~> 2.0') if RUBY_VERSION >= '2.3'
    s.add_dependency('sinatra', '~> 1.4') if RUBY_VERSION < '2.2'
    s.add_dependency('sinatra', '~> 2.0') if RUBY_VERSION >= '2.2'

  rescue => e
    warn "#{$0}: #{e}"
    exit!
  end

  s.add_dependency('puma', '~> 3.10')
  s.add_dependency('rest-client', '~> 2.0')
  s.add_dependency('json', '~> 2.1')
  s.add_dependency('sinatra-basic-auth', '~> 0')

  s.add_development_dependency('rspec', '~> 3.7')
  s.add_development_dependency('rspec-nc', '~> 0.3')
  s.add_development_dependency('guard', '~> 2.14')
  s.add_development_dependency('guard-rspec', '~> 4.7')
  s.add_development_dependency('pry', '~> 0.9')
  s.add_development_dependency('pry-remote', '~> 0.1')
  s.add_development_dependency('pry-nav', '~> 0.2')
end
