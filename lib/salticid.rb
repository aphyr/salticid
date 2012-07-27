require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'net/ssh/gateway'

$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'salticid/version'

class Salticid
  def self.log(str)
    File.open('salticid.log', 'a') do |f|
      f.puts str
    end
  end

  $LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'net-ssh-shell', 'lib'))
  require 'monkeypatch'
  require 'snippets/init'
  require 'salticid/message'
  require 'salticid/task'
  require 'salticid/role'
  require 'salticid/role_proxy'
  require 'salticid/host'
  require 'salticid/gateway'
  require 'salticid/group'

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
      gw = Salticid::Gateway.new(name, :salticid => self)
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
      host = Salticid::Host.new(name, :salticid => self)
      @hosts << host
    end

    if block_given?
      host.instance_exec &block
    end

    host
  end

  # Tries to guess what hosts we would run the given string on.
  def hosts_for(string)
    first = string[/^(\w+)\.\w+/, 1]
    if role = @roles.find { |r| r.name == first }
      return role.hosts
    else
      raise "Sorry, I didn't understand what hosts to run #{string.inspect} on."
    end
  end

  # Assigns a group to this Salticid. Runs the optional block in the group's
  # context.  Returns the group.
  def group(name, &block)
    # Get group
    group = name if name.kind_of? Salticid::Group 
    name = name.to_s
    group ||= @groups.find{|g| g.name == name}
    group ||= Salticid::Group.new(name, :salticid => self)

    # Store
    @groups |= [group]

    # Run block
    if block_given?
      group.instance_exec &block
    end

    group
  end

  # Loads one or more file globs into the current salticid.
  def load(*globs)
    skips = globs.grep(/^-/)
    (globs - skips).each do |glob|
      glob += '.rb' if glob =~ /\*$/
      Dir.glob(glob).sort.each do |path|
        next unless File.file? path
        next if skips.find {|pat| path =~ /#{pat[1..-1]}$/}
        instance_eval(File.read(path), path)
      end
    end
  end

  # Defines a new role. A role is a package of tasks.
  def role(name, &block)
    name = name.to_s

    unless role = @roles.find{|r| r.name == name}
      role = Salticid::Role.new(name, :salticid => self)
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
      task = Salticid::Task.new(name, :salticid => self)
      @tasks << task
    end
  
    if block_given?
      task.block = block
    end

    task 
  end

  def to_s
    "Salticid"
  end

  # An involved description of the salticid
  def to_string
    h = ''
    h << "Groups\n"
    groups.each do |group|
      h << "  #{group}\n"
    end
    
    h << "\nHosts:\n"
    hosts.each do |host|
      h << "  #{host}\n"
    end
    
    h << "\nRoles\n"
    roles.each do |role|
      h << "  #{role}\n"
    end

    h << "\nTop-level tasks\n"
    tasks.each do |task|
      h << "  #{task}\n"
    end

    h
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
