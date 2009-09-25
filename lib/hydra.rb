require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'net/ssh/gateway'

$LOAD_PATH.unshift(File.dirname(__FILE__))

class Hydra
  $LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'net-ssh-shell', 'lib'))
  require 'monkeypatch'
  require 'snippets/instance_exec'
  require 'hydra/task'
  require 'hydra/role'
  require 'hydra/role_proxy'
  require 'hydra/host'
  require 'hydra/gateway'

  attr_accessor :gw, :hosts, :roles, :tasks

  def initialize
    @gw = nil
    @hosts = []
    @roles = []
    @tasks = []
  end

  # Default SSH gateway.
  def gw(name = nil, &block)
    # Get gateway from cache or set new one.
    if name
      # Set gateway
      @gw = Hydra::Gateway.new(name, :hydra => self)
    end

    if block_given?
      @gw.instance_exec &block
    end

    @gw
  end

  def host(name, &block)
    name = name.to_s
    unless host = @hosts.find{|h| h.name == name}
      host = Hydra::Host.new(name, :hydra => self)
      @hosts << host
    end

    if block_given?
      host.instance_exec &block
    end

    host
  end

  # Loads one or more file globs into the current hydra.
  def load(*globs)
    globs.each do |glob|
      glob += '.rb' if glob =~ /\*$/
      Dir.glob(glob).each do |path|
        next unless File.file? path
        instance_eval(File.read(path), path)
      end
    end
  end

  # Defines a new role. A role is a package of tasks.
  def role(name, &block)
    name = name.to_s

    unless role = @roles.find{|r| r.name == name}
      role = Hydra::Role.new(name, :hydra => self)
      @roles << role
    end

    if block_given?
      role.instance_eval &block
    end

    role
  end
 
  # Finds (and optionally defines) a task.
  # task :foo => returns a Task
  # task :foo do ... end => defines a Task with given block
  def task(name, &block)
    name = name.to_s

    unless task = @tasks.find{|t| t.name == name}
      task = Hydra::Task.new(name, :hydra => self)
      @tasks << task
    end
  
    if block_given?
      task.block = block
    end

    task 
  end
end
