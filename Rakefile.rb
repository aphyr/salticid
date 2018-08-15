$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'rubygems'
require 'salticid/version'
require 'find'
require 'rubygems/package_task'
 
# Don't include resource forks in tarballs on Mac OS X.
ENV['COPY_EXTENDED_ATTRIBUTES_DISABLE'] = 'true'
ENV['COPYFILE_DISABLE'] = 'true'
 
# Gemspec
gemspec = Gem::Specification.new do |s|
  s.name = 'salticid'
  s.version = Salticid::VERSION
  s.author = 'Kyle Kingsbury'
  s.email = 'aphyr@aphyr.com'
  s.homepage = 'https://github.com/aphyr/salticid'
  s.platform = Gem::Platform::RUBY
  s.summary = 'Run commands over SSH, with Ruby magic.'
 
  s.files = FileList['{lib}/**/*', 'LICENSE', 'README.markdown'].to_a
  s.executables = ['salticid']
  s.require_path = 'lib'
  s.has_rdoc = true
 
  s.required_ruby_version = '>= 1.8.7'
 
  s.add_dependency('trollop', '~> 1.16.2')
  s.add_dependency('net-scp')
  s.add_dependency('net-ssh')
  s.add_dependency('curses')
  s.add_dependency('net-ssh-gateway')
  s.add_dependency('net-ssh-multi')
end

Gem::PackageTask.new(gemspec) do |pkg|
end
