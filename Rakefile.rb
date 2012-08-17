$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'rubygems'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'salticid/version'
require 'find'
 
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
  s.executables = []
  s.require_path = 'lib'
  s.has_rdoc = true
 
  s.required_ruby_version = '>= 1.8.7'
 
  s.add_dependency('trollop', '~> 1.16.2')
  s.add_dependency('net-scp')
  s.add_dependency('net-ssh')
  s.add_dependency('net-ssh-gateway')
  s.add_dependency('net-ssh-multi')
  s.add_dependency('ncurses', '~> 0.9.1')
end
 
Rake::GemPackageTask.new(gemspec) do |p|
  p.need_tar_gz = true
end
 
Rake::RDocTask.new do |rd|
  rd.main = 'Risky'
  rd.title = 'Risky'
  rd.rdoc_dir = 'doc'
 
  rd.rdoc_files.include('lib/**/*.rb')
end
 
desc "install Risky"
task :install => :gem do
  sh "gem install #{File.dirname(__FILE__)}/pkg/risky-#{Risky::VERSION}.gem"
end
