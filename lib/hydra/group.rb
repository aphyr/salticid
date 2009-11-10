class Hydra::Group
  # A collection of hosts and other groups.
  
  attr_reader :name
  attr_accessor :parent
  attr_accessor :groups, :hosts

  def initialize(name, opts = {})
    @name = name.to_s
    @hydra = opts[:hydra]
    @parent = opts[:parent]
    @hosts = []
    @groups = []
  end

  def ==(other)
    self.class == other.class and 
      self.name == other.name and 
      self.parent == other.parent
  end

  # Runs the block in the context of each.
  def each_host(&block)
    hosts.each do |host|
      host.instance_exec &block
    end
  end

  # Finds all hosts (recursively) that are members of this group or subgroups.
  def hosts
    @hosts + @groups.map { |m|
      m.hosts
    }.flatten.uniq
  end

  # Creates a sub-group of this group.
  def group(name, &block)
    # Get group
    name = name.to_s
    group = @groups.find{|g| g.name == name}
    group ||= Hydra::Group.new(name, :hydra => @hydra, :parent => self)

    # Store
    @groups |= [group]

    # Run block
    if block
      group.instance_exec &block
    end

    group
  end

  # Adds a host (by name) to the group. Returns the host.
  def host(name)
    host = @hydra.host name
    host.groups |= [self]
    @hosts |= [host]
  end
  
  def inspect
    "#<Hydra::Group #{path}>"
  end

  # Unknown methods are resolved as groups, then hosts. Blocks are instance_exec'd in the found context.
  def method_missing(meth, &block)
    name = meth.to_s
    found = @groups.find { |g| g.name == name }
    found ||= @hosts.find { |h| h.name == name }

    unless found
      raise NoMethodError
    end

    if block
      found.instance_exec &block
    end

    found
  end

  def path
    if @parent
      @parent.path + '/' + @name
    else
      '/' + @name
    end
  end

  def to_s
    @name
  end

  def to_string
    h = "Group #{@name}:\n"
    h << "  Hosts:\n"
    h << hosts.map { |h| "    #{h}" }.join("\n")
  end
end
