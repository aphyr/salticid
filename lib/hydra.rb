require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'net/ssh/gateway'

$LOAD_PATH.unshift(File.dirname(__FILE__))

class Hydra
  $LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'net-ssh-shell', 'lib'))
  require 'monkeypatch'
  require 'snippets/init'
  require 'hydra/task'
  require 'hydra/role'
  require 'hydra/role_proxy'
  require 'hydra/host'
  require 'hydra/gateway'
  require 'hydra/group'

  attr_accessor :gw, :groups, :hosts, :roles, :tasks

  def initialize
    @gw = nil
    @hosts = []
    @groups = []
    @roles = []
    @tasks = []
  end

  # Define a gateway.
  def gw(name = nil, &block)
    if name == nil
      return @gw
    end

    # Get gateway from cache or set new one.
    name = name.to_s

    unless gw = @hosts.find{|h| h.name == name}
      gw = Hydra::Gateway.new(name, :hydra => self)
      @hosts << gw
      # Set default gw
      @gw = gw 
    end


    if block_given?
      gw.instance_exec &block
    end

    gw
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

  # Assigns a group to this Hydra. Runs the optional block in the group's
  # context.  Returns the group.
  def group(name, &block)
    # Get group
    group = name if name.kind_of? Hydra::Group 
    name = name.to_s
    group ||= @groups.find{|g| g.name == name}
    group ||= Hydra::Group.new(name, :hydra => self)

    # Store
    @groups |= [group]

    # Run block
    if block_given?
      group.instance_exec &block
    end

    group
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

  # Unknown methods are resolved as groups, then hosts, then roles, then tasks.
  # Can you think of a better order?
  #
  # Blocks are instance_exec'd in the context of the found object.
  def method_missing(meth, &block)
    name = meth.to_s

    found = @groups.find { |g| g.name == name }
    found ||= @hosts.find { |h| h.name == name }
    found ||= @roles.find { |r| r.name == name }
    found ||= @tasks.find { |t| t.name == name }

    unless found
      raise NoMethodError
    end

    if block
      found.instance_exec &block
    end

    found
  end
end
