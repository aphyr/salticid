class Hydra::Host
  SKIP_BEFORE_CMDS = [
    /^cd\b/,
    /^pwd\b/,
    /^sudo /
  ]

  attr_accessor :name, :user, :roles, :tasks, :hydra
  def initialize(name, opts = {})
    @name = name.to_s
    @user = opts[:user].to_s
    @roles = opts[:roles] || []
    @tasks = opts[:tasks] || []
    @hydra = opts[:hydra]

    @before_cmds = []
  end

  def ==(other)
    self.name == other.name
  end

  # Appends the given string to a file.
  def append(str, file, opts = {:uniq => false})
    if opts[:uniq] and exists? file
      # Check to ensure the file does not contain the line already.
      begin
        grep(str, file) or raise
      rescue
        return nil
      end
    end

    if str =~ /EOF/
      raise "Sorry, can't append this string, it has an EOF in it:\n#{str}"
    end

    puts "cat >>#{escape(file)} <<EOF\n#{str}EOF"
    execute!("cat >>#{escape(file)} <<EOF\n#{str}EOF")
  end

  # All calls to exec! within this block are prefixed by sudoing to the user.
  def as(user = nil)
    old_cmds = @before_cmds

    if user.nil?
      @before_cmds = ["sudo"]
    else
      old_user, @user = @user, user
      @before_cmds = ["sudo -u #{escape(user)}"]
    end

    yield

    @user = old_user
    @before_cmds = old_cmds
  end

  # Changes our working directory.
  def cd(dir = nil)
    dir ||= homedir
    dir = expand_path(dir)
    @cwd = dir
  end

  # Changes the mode of a file. Mode is numeric.
  def chmod(mode, path)
    exec! "chmod #{mode.to_s(8)} #{escape(expand_path(path))}"
  end

  # Changes the mode of a file, recursively. Mode is numeric.
  def chmod_r(mode, path)
    exec! "chmod -R #{mode.to_s(8)} #{escape(expand_path(path))}"
  end

  # Returns our idea of what the current working directory is.
  # If @cwd has not been set (i.e. by cd(),) / is used.
  def cwd
    begin
      @cwd ||= '/'
    rescue
      @cwd
    end
  end

  # Returns true if a directory exists
  def dir?(path)
    begin
      ftype(path) == 'directory'
    rescue
      false
    end
  end

  # Download a file to the local host. Local defaults to remote if not
  # specified.
  def download(remote, local=nil, opts = {})
    local ||= remote
    remote = expand_path remote
    ssh.scp.download!(remote, local, opts)
  end

  # Quotes a string for inclusion in a bash command line
  def escape(string)
    return '' if string.nil?
    return string unless string.to_s =~ /[\\\$`"]/
    '"' + string.to_s.gsub(/[\\\$`"]/) { |match| '\\' + match } + '"'
  end
  
  # Runs a remote command.
  def exec!(command, opts = {})
    # Options
    stdout = ''
    stderr = ''
    defaults = {
    }
    
    opts = defaults.merge opts

    unless SKIP_BEFORE_CMDS.any? { |cmd| cmd  === command.to_s }
      command = (@before_cmds + [command]).join(' ')
    end
 
    # Before execution, cd to cwd
    command = "cd #{escape(cwd)}; " + command

    # After command, add a semicolon...
    unless command =~ /;\s*$/
      command += ';'
    end

    # Then echo the exit status.
    command += ' echo $?; '

    buffer = ''
    status = nil

    # Run ze command with callbacks.
    # Return status.
    channel = ssh.open_channel do |ch|
      ch.exec command do |ch, success|
        raise "could not execute command" unless success

        # Handle STDOUT
        ch.on_data do |c, data|
          # Could this data be the status code?
          if pos = (data =~ /(\d{1,3})\n$/)
            # Set status
            status = $1

            # Flush old buffer
            opts[:stdout].call(buffer) if opts[:stdout]
            stdout << buffer

            # Save candidate status code
            buffer = data[pos .. -1]

            # Write the other part of the string to the callback
            opts[:stdout].call(data[0...pos]) if opts[:stdout]
            stdout << data[0...pos]
          else
            # Write buffer + data to callback
            opts[:stdout].call(buffer + data) if opts[:stdout]
            stdout << buffer + data
            buffer = ''
          end
        end

        # Handle STDERR
        ch.on_extended_data do |c, type, data|
          if type == 1
            # STDERR
            opts[:stderr].call(data) if opts[:stderr]
            stderr << data
          end
        end
        
        # Handle close
        ch.on_close do
        end
      end
    end

    # Wait for the command to complete.
    channel.wait

    # Make sure we have our status.
    if status.nil? or status.empty?
      raise "empty status in host#exec(), hmmm"
    end

    # Check status.
    status = status.to_i
    if status != 0
      raise "#{command} exited with non-zero status #{status}!\nSTDERR:\n#{stderr}\nSTDOUT:\n#{stdout}"
    end

    stdout.chomp
  end

  # Returns true when a file exists, otherwise false
  def exists?(path)
    true if ftype(path) rescue false
  end

  # Generates a full path for the given remote path.
  def expand_path(path)
    path = path.gsub(/~(\w+)?/) { |m| homedir($1) }
    File.expand_path(path, cwd.to_s)
  end
  
  # Returns true if a regular file exists.
  def file?(path)
    ftype(path) == 'file' rescue false
  end

  # Returns the filetype, as string. Raises exceptions on failed stat.
  def ftype(path)
    path = expand_path(path)
    begin
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
        raise RuntimeError, "unknown filetype #{str}"
      end
    rescue
      raise RuntimeError, "stat #{self}:#{path} failed - #{str}"
    end
  end

  # Returns the gateway for this host.
  def gw
    @hydra.gw
  end

  # Returns the home directory of the given user, or the current user if
  # none specified.
  def homedir(user = @user)
    exec! "awk -F: -v v=#{escape(user)} '{if ($1==v) print $6}' /etc/passwd"
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

  # Sets or gets the name of this host.
  def name(name = nil)
    if name
      @name = name.to_s
    else
      @name
    end
  end

  # Finds a task for this host, by name.
  def resolve_task(name)
    name = name.to_sym
    @tasks.each do |task|
      return task if task.name == name
    end
    @roles.each do |role|
      role.tasks.each do |task|
        return task if task.name == name
      end
    end
    @hydra.tasks.each do |task|
      return task if task.name == name
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
    ssh
    task_names.each do |name|
      task = resolve_task(name) or raise RuntimeError, "no such task #{name} on #{self}"
      task.run(self)
    end
  end

  # Opens an SSH connection and stores the connection in @ssh.
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
  # the replacement. Otherwise it inherits ownership from the parent directory.
  def sudo_upload(local, remote, opts={})
    remote = expand_path remote

    # TODO: umask this?
    local_mode = File.stat(local).mode & 07777
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
      user = sudo('stat', '-c', '%U', File.dirname(remote)).strip
      group = sudo('stat', '-c', '%G', File.dirname(remote)).strip
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

  # Returns an SSH::Gateway object for connecting to this host, or nil if no
  # gateway is needed.
  def tunnel
    if gw
      # We have a gateway host.
      @tunnel ||= gw.gateway_tunnel
    end
  end

  # Upload a file to the server. Remote defaults to local if not specified.
  def upload(local, remote = nil, opts={})
    remote ||= local
    remote = expand_path remote
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
