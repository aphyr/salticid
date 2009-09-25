class Hydra::Role
  # A role is a list of tasks.
  attr_reader :name, :tasks, :hydra

  def initialize(name, opts = {})
    @name = name.to_s
    @tasks = []
    @hydra = opts[:hydra]
  end

  # Runs the block in the context of each.
  def each_host(&block)
    hosts.each do |host|
      host.instance_exec &block
    end
  end

  # Returns an array of all hosts in this hydra which include this role.
  def hosts
    @hydra.hosts.select do |host|
      host.roles.include? self
    end
  end

  def inspect
    "#<Role #{name} tasks=#{@tasks.inspect}>"
  end

  # Sets or gets the name of this role.
  def name(name = nil)
    if name
      @name = name.to_s
    else
      @name
    end
  end

  # Finds (and optionally defines) a task.
  # 
  # Tasks are first resolved in the role's task list, then in the Hydra's task
  # list. Finally, tasks are created from scratch. Any invocation of task adds
  # that task to this role.
  # 
  # If a block is given, the block is assigned to the local (role) task. The
  # task is dup'ed to prevent modifying a possible global task.
  #
  # The task is returned at the end of the method.
  def task(name, &block)
    name = name.to_s

    if task = @tasks.find{|t| t.name == name}
      # Found in self
    elsif (task = @hydra.tasks.find{|t| t.name == name}) and not block_given?
      # Found in hydra
      @tasks << task
    else
      # Create new task in self
      task = Hydra::Task.new(name, :hydra => @hydra)
      @tasks << task
    end

    if block_given?
      # Remove the task from our list, and replace it with a copy.
      # This is to prevent local declarations from clobbering global tasks.
      i = @tasks.index(task) || @task.size
      task = task.dup
      task.block = block
      @tasks[i] = task
    end

    task
  end

  def to_s
    @name.to_s
  end
end
