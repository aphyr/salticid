class Hydra::Host
  SKIP_BEFORE_CMDS = [
    /^cd /
  ]

  attr_accessor :name, :user, :roles, :tasks, :hydra
  def initialize(name, opts = {})
    @name = name
    @user = opts[:user]
    @roles = opts[:roles] || []
    @tasks = opts[:tasks] || []
    @hydra = opts[:hydra]
    @before_cmds = []
  end

  def ==(other)
    self.name == other.name
  end

  # all calls to exec! within this block are prefixed by sudoing to the user.
  def as(user = nil)
    old_cmds = @before_cmds

    if user.nil?
      @before_cmds = ["sudo"]
    else
      @before_cmds = ["sudo -u #{escape(user)}"]
    end

    yield

    @before_cmds = old_cmds
  end

  # Changes the mode of a file. Mode is numeric.
  def chmod
    chmod mode.to_s(8), path
  end

  # Changes the mode of a file, recursively. Mode is numeric.
  def chmod_r(mode, path)
    chmod '-R', mode.to_s(8), path
  end

  # Returns true if a directory exists
  def dir?(path)
    ftype(path) == 'directory' rescue false
  end

  # Download a file to the local host. Local defaults to remote if not
  # specified.
  def download(remote, local=nil, opts = {})
    local ||= remote
    ssh.scp.download!(remote, local, opts)
  end

  # Quotes a string for inclusion in a bash command line
  def escape(string)
    '"' + string.to_s.gsub(/[\\\$`"]/) { |match| '\\' + match } + '"'
  end
  
  # Runs a remote command.
  def exec!(command)
    unless SKIP_BEFORE_CMDS.any? { |cmd| cmd  === command.to_s }
      command = (@before_cmds + [command]).join(' ')
    end
    
    if @shell
      # Run in shell
      status, output = @shell.exec! command
      raise RuntimeError, "#{command} returned non-zero exit status #{status}:\n#{output}" if status != 0
      output
    else
      response = ssh.exec! *args
    end
    response
  end

  # Returns true when a file exists, otherwise false
  def exists?(path)
    true if ftype(path) rescue false
  end

  # Returns true if a regular file exists.
  def file?(path)
    ftype(path) == 'file' rescue false
  end

  # Returns the filetype, as string. Raises exceptions on failed stat.
  def ftype(path)
    str = self.stat('-c', '%F', path).strip
    case str
    when /no such file or directory/i
      raise Errno::ENOENT, "#{self}:#{path} does not exist"
    when 'regular file'
      'file'
    when 'directory'
      'directory'
    when 'character special file'
      'characterSpecial'
    when 'block special file'
      'blockSpecial'
    when /link/
      'link'
    when /socket/
      'socket'
    when /fifo|pipe/
      'fifo'
    else
      raise RuntimeError, "stat #{self}:#{path} failed - #{stat}"
    end
  end

  # Returns the gateway for this host.
  def gw
    @hydra.gw
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

  # Returns the file mode of a remote file.
  def mode(path)
    stat('-c', '%a', path).oct
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

  # Removes a remote file
  def rm(path, rf=false)
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
    ssh
    task_names.each do |name|
      task = resolve_task(name) or raise RuntimeError, "no such task #{name} on #{self}"
      task.run(self)
    end
  end

  # Opens a shell. Subsequent exec! commands are interpreted by the shell.
  def shell(&block)
    ssh.shell do |shell|
      old_shell, @shell = @shell, shell
      instance_exec(&block)
      @shell = old_shell
    end
  end

  # Opens an SSH tunnel and stores the connection in @ssh.
  def ssh
    if @ssh and not @ssh.closed?
      return @ssh
    end

    if tunnel
      @ssh = tunnel.ssh(name, user)
    else
      @ssh = Net::SSH.start(name, user)
    end
  end

  def sudo(*args, &block)
    if block_given?
      as nil, &block
    else
      method_missing(:sudo, *args)
    end
  end

  # Uploads a file and places it in the final destination as root.
  # If the file already exists, its ownership and mode are used for
  # the replacement.
  def sudo_upload(local, remote, opts={})
    # TODO: umask this?
    local_mode = File.stat(local).mode
    File.chmod 0600, local
    
    # Get temporary filename
    tmpfile = '/'
    while exists? tmpfile
      tmpfile = '/tmp/sudo_upload_' + Time.now.to_f.to_s
    end

    # Upload
    upload local, tmpfile, opts

    # Get remote mode/user/group
    if exists? remote
      mode = self.mode remote
      user = sudo('stat', '-c', '%U', remote).strip
      group = sudo('stat', '-c', '%G', remote).strip
    else
      user = 'root'
      group = 'root'
      mode = local_mode
    end

    # Move and chmod
    sudo 'mv', tmpfile, remote
    sudo 'chmod', mode.to_s(8), remote
    sudo 'chown', "#{user}:#{group}", remote
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

  # Returns an SSH::Gateway object for connecting to this host, or nil if
  # no gateway is configured.
  def tunnel
    if gw
      @tunnel ||= Net::SSH::Gateway.new(gw.name, gw.user)
    end
  end

  # Upload a file to the server. Remote defaults to local if not specified.
  def upload(local, remote = nil, opts={})
    remote ||= local
    ssh.scp.upload!(local, remote, opts)
  end

  def user(user = nil)
    if user
      @user = user
    else
      @user
    end
  end
end
