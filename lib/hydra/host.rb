class Hydra::Host
  attr_accessor :name, :user, :roles, :tasks, :hydra
  def initialize(name, opts = {})
    @name = name
    @user = opts[:user]
    @roles = opts[:roles] || []
    @tasks = opts[:tasks] || []
    @hydra = opts[:hydra]
  end

  def ==(other)
    self.name == other.name
  end

  # Quotes a string for inclusion in a bash command line
  def escape(string)
    '"' + string.to_s.gsub(/[\\\$`"]/) { |match| '\\' + match } + '"'
  end

  # Returns true if a directory exists
  def dir?(path)
    ftype(path) == :directory rescue false
  end

  # Runs a remote command.
  def exec!(*args)
    response = @ssh.exec! *args
    response
  end

  # Returns true when a file exists, otherwise false
  def exists?(path)
    true if ftype(path) rescue false
  end

  # Returns true if a regular file exists.
  def file?(path)
    ftype(path) == :file rescue false
  end

  # Returns the filetype, as symbol. Raises exceptions on failed stat.
  def ftype(path)
    stat = self.stat path
    begin
      stat.split("\n")[1].split(/\s+/).last.to_sym
    rescue
      if stat =~ /no such file or directory/i
        raise Errno::ENOENT, "#{self}:#{path} does not exist"
      else
        raise RuntimeError, "stat #{self}:#{path} failed - #{stat}"
      end
    end
  end

  def inspect
    "#<#{@user}@#{@name} roles=#{@roles.inspect} tasks=#{@tasks.inspect}>"
  end

  # Missing methods are resolved as follows:
  # 1. From task_resolve
  # 2. Converted to a command string and exec!'ed
  def method_missing(meth, *args)
    if task = resolve_task(meth)
      task.run(self, *args)
    else
      str = ([meth] + args.map{|a| escape(a)}).join(' ')
      exec! str
    end
  end

  # Opens a shell.
  def shell(&block)
    ssh.shell do |sh|
      sh.instance_exec(&block)
    end
  end

  # Opens an SSH tunnel and stores the connection in @ssh.
  def ssh
    if @ssh
      if @ssh.open?
        return @ssh
      else
        @ssh.close
        @ssh = @hydra.ssh self
      end
    else
      @ssh = @hydra.ssh self
    end
  end

  # Finds a task for this host, by name.
  def resolve_task(name)
    @tasks.each do |task|
      return task if task.name == name
    end
    @roles.each do |role|
      role.tasks.each do |task|
        return task if task.name == name
      end
    end
    nil
  end

  # Assigns roles to a host from the Hydra. Roles are unique in hosts; repeat
  # assignments will not result in more than one copy of the role.
  def role(role)
    @roles = @roles | [@hydra.role(role)]
  end

  # Run a task, tasks, or all defined tasks.
  # Tasks are run in the order given.
  # Tasks are run with this host as context.
  def run(*task_names)
    ssh do
      task_names.each do |name|
        task = resolve_task(name) or raise RuntimeError, "no such task #{name} on #{self}"
        task.run(self)
      end
    end
  end

  # Finds (and optionally defines) a task.
  # 
  # Tasks are first resolved in the host's task list, then in the Hydra's task
  # list. Finally, tasks are created from scratch. Any invocation of task adds
  # that task to this host.
  # 
  # If a block is given, the block is assigned to the local (host) task. The
  # task is dup'ed to prevent modifying a possible global task.
  #
  # The task is returned at the end of the method.
  def task(name, &block)
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

  def user(user = nil)
    if user
      @user = user
    else
      @user
    end
  end
end
