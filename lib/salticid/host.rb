class Salticid::Host
  attr_accessor :env, :name, :user, :groups, :roles, :tasks, :salticid, :password

  def initialize(name, opts = {})
    @name = name.to_s
    @user = opts[:user].to_s
    @groups = opts[:groups] || []
    @roles = opts[:roles] || []
    @tasks = opts[:tasks] || []
    @salticid = opts[:salticid]
    @sudo = nil

    @on_log = proc { |message| }

    @ssh_lock = Mutex.new

    @env = {}
    @cwd = nil
    @role_proxies = {}
  end

  def ==(other)
    self.name == other.name
  end

  # Appends the given string to a file.
  # Pass :uniq => true to only append if the string is not already present in
  # the file.
  def append(str, file, opts = {})
    file = expand_path(file)
    if opts[:uniq] and exists? file
      # Check to ensure the file does not contain the line already.
      begin
        grep(str, file) or raise
      rescue
        # We're clear, go ahead.
        tee '-a', file, :stdin => str
      end
    else
      # No need to check, just append.
      tee '-a', file, :stdin => str
    end
  end

  # All calls to exec! within this block are prefixed by sudoing to the user.
  def as(user = nil)
    old_sudo, @sudo = @sudo, (user || 'root')
    yield
    @sudo = old_sudo
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

  # Returns current working directory. Tries to obtain it from exec 'pwd',
  # but falls back to /.
  def cwd
    @cwd ||= begin
      exec! 'pwd'
    rescue => e
      raise e
      '/'
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

  # Downloads a file from the remote server. Local defaults to remote filename
  # (in current path) if not specified.
  def download(remote, local = nil, opts = {})
    remote_filename ||= File.split(remote).last
    if File.directory? local
      local = File.join(local, remote_filename)
    else
      local = remote_filename
    end

    remote = expand_path remote
    log "downloading from #{remote.inspect} to #{local.inspect}"
    ssh.scp.download!(remote, local, opts)
  end
  
  # Quotes a string for inclusion in a bash command line
  def escape(string)
    return '' if string.nil?
    return string unless string.to_s =~ /[\\\$`" \(\)\{\}\[\]]/
    '"' + string.to_s.gsub(/[\\\$`"]/) { |match| '\\' + match } + '"'
  end
  
  # Runs a remote command.  If a block is given, it is run in a new thread
  # after stdin is sent. Its sole argument is the SSH channel for this command:
  # you may use send_data to write to the processes stdin, and use ch.eof! to
  # close stdin. ch.close will stop the remote process.
  #
  # Options:
  #   :stdin => Data piped to the process' stdin.
  #   :stdout => A callback invoked when stdout is received from the process.
  #              The argument is the data received.
  #   :stderr => Like stdout, but for stderr.
  #   :echo => Prints stdout and stderr using print, if true.
  #   :to => Shell output redirection to file. (like cmd >/foo)
  #   :from => Shell input redirection from file. (like cmd </foo)
  def exec!(command, opts = {}, &block)
    # Options
    stdout = ''
    stderr = ''
    defaults = {
      :check_exit_status => true
    }
    
    opts = defaults.merge opts

    # First, set up the environment...
    if @env.size > 0
      command = (
        @env.map { |k,v| k.to_s.upcase + '=' + v } << command
      ).join(' ')
    end

    # Before execution, cd to cwd
    command = "cd #{escape(@cwd)}; " + command

    # Input redirection
    if opts[:from]
      command += " <#{escape(opts[:from])}"
    end

    # Output redirection
    if opts[:to]
      command += " >#{escape(opts[:to])}"
    end

    # After command, add a semicolon...
    unless command =~ /;\s*$/
      command += ';'
    end

    # Then echo the exit status.
    command += ' echo $?; '


    # If applicable, wrap the command in a sudo subshell...
    if @sudo
      command = "sudo -S -u #{@sudo} bash -c #{escape(command)}"
      if @password
        opts[:stdin] = @password + "\n" + opts[:stdin].to_s
      end
    end

    buffer = ''
    echoed = 0
    status = nil
    written = false

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
          
          if opts[:echo] and echoed < stdout.length
            stdout[echoed..-1].split("\n")[0..-2].each do |fragment|
              echoed += fragment.length + 1
              log fragment
            end
          end
        end

        # Handle STDERR
        ch.on_extended_data do |c, type, data|
          if type == 1
            # STDERR
            opts[:stderr].call(data) if opts[:stderr]
            stderr << data
            log :stderr, stderr if opts[:echo]
          end
        end
        
        # Write stdin
        if opts[:stdin]
          ch.on_process do
            unless written
              ch.send_data opts[:stdin]
              written = true
            else
              # Okay, we wrote stdin
              unless block or ch.eof?
                ch.eof!
              end
            end
          end
        end

        # Handle close
        ch.on_close do
          if opts[:echo]
            # Echo last of input data
            stdout[echoed..-1].split("\n").each do |fragment|
              echoed += fragment.length + 1
              log fragment
            end
          end
        end
      end
    end
    
    if block
      # Run the callback
      callback_thread = Thread.new do
        if opts[:stdin]
          # Wait for stdin to be written before calling...
          until written
            sleep 0.1
          end
        end

        block.call(channel)
      end
    end

    # Wait for the command to complete.
    channel.wait

    # Let the callback thread finish as well
    callback_thread.join if callback_thread

    if opts[:check_exit_status]
      # Make sure we have our status.
      if status.nil? or status.empty?
        raise "empty status in host#exec() for #{command}, hmmm"
      end

      # Check status.
      status = status.to_i
      if  status != 0
        raise "#{command} exited with non-zero status #{status}!\nSTDERR:\n#{stderr}\nSTDOUT:\n#{stdout}"
      end
    end

    stdout.chomp
  end

  # Returns true when a file exists, otherwise false
  def exists?(path)
    true if ftype(path) rescue false
  end

  # Generates a full path for the given remote path.
  def expand_path(path)
    path = path.to_s.gsub(/~(\w+)?/) { |m| homedir($1) }
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
      when 'regular empty file'
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

  # Abusing convention slightly...
  # Returns the group by name if this host belongs to it, otherwise false.
  def group?(name)
    name = name.to_s
    @groups.find{ |g| g.name == name } || false
  end

  # Adds this host to a group.
  def group(name)
    group = name if name.kind_of? Salticid::Group
    group ||= @salticid.group name
    group.hosts |= [self]
    @groups |= [group]
    group
  end

  # Returns the gateway for this host.
  def gw(gw = nil)
    if gw
      @gw = @salticid.host(gw)
    else
      @gw
    end
  end

  # Returns the home directory of the given user, or the current user if
  # none specified.
  def homedir(user = (@sudo||@user))
    exec! "awk -F: -v v=#{escape(user)} '{if ($1==v) print $6}' /etc/passwd"
  end
 
  def inspect
    "#<#{@user}@#{@name} roles=#{@roles.inspect} tasks=#{@tasks.inspect}>"
  end

  # Issues a logging statement to this host's log.
  # log :error, "message"
  # log "message" is the same as log "info", "message"
  def log(*args)
    begin
      @on_log.call Message.new(*args)
    rescue
      # If the log handler is broken, keep going.
    end
  end

  # Missing methods are resolved as follows:
  # 0. Create a RoleProxy from a Role on this host
  # 1. From task_resolve
  # 2. Converted to a command string and exec!'ed
  def method_missing(meth, *args, &block)
    if meth.to_s == "to_ary"
      raise NoMethodError
    end

    if args.empty? and rp = role_proxy(meth)
      rp
    elsif task = resolve_task(meth)
      task.run(self, *args, &block)
    else
      if args.last.kind_of? Hash
        opts = args.pop
      else
        opts = {}
      end
      str = ([meth] + args.map{|a| escape(a)}).join(' ')
      exec! str, opts, &block
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

  def on_log(&block)
    @on_log = block
  end

  # Finds a task for this host, by name.
  def resolve_task(name)
    name = name.to_s
    @tasks.each do |task|
      return task if task.name == name
    end
    @salticid.tasks.each do |task|
      return task if task.name == name
    end
    nil
  end

  # Assigns roles to a host from the Salticid. Roles are unique in hosts; repeat
  # assignments will not result in more than one copy of the role.
  def role(role)
    @roles = @roles | [@salticid.role(role)]
  end

  # Does this host have the given role?
  def role?(role)
    @roles.any? { |r| r.name == role.to_s }
  end

  # Returns a role proxy for role on this host, if we have the role.
  def role_proxy(name)
    if role = roles.find { |r| r.name == name.to_s }
      @role_proxies[name.to_s] ||= RoleProxy.new(self, role)
    end
  end

  # Runs the specified task on the given role. Raises NoMethodError if
  # either the role or task do not exist.
  def run(role, task, *args)
    if rp = role_proxy(role)
      rp.__send__(task, *args)
    else
      raise NoMethodError, "No such role #{role.inspect} on #{self}"
    end
  end

  # Opens an SSH connection and stores the connection in @ssh.
  def ssh
    @ssh_lock.synchronize do
      if @ssh and not @ssh.closed?
        return @ssh
      end

      if tunnel
        @ssh = tunnel.ssh(name, user)
      else
        @ssh = Net::SSH.start(name, user)
      end
    end
  end

  # If a block is given, works like #as. Otherwise, just execs sudo with the
  # given arguments.
  def sudo(*args, &block)
    if block_given?
      as *args, &block
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
    sudo do
      if exists? remote
        mode = self.mode remote
        user = stat('-c', '%U', remote).strip
        group = stat('-c', '%G', remote).strip
      else
        user = stat('-c', '%U', File.dirname(remote)).strip
        group = stat('-c', '%G', File.dirname(remote)).strip
        mode = local_mode
      end

      # Move and chmod
      mv tmpfile, remote
      chmod mode, remote
      chown "#{user}:#{group}", remote
    end
  end

  # Finds (and optionally defines) a task.
  # 
  # Tasks are first resolved in the host's task list, then in the Salticid's task
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
    elsif (task = @salticid.tasks.find{|t| t.name == name}) and not block_given?
      # Found in salticid
      @tasks << task
    else
      # Create new task in self
      task = Salticid::Task.new(name, :salticid => @salticid)
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

  def to_string
    h = "Host #{@name}:\n"
    h << "  Groups: #{groups.map(&:to_s).sort.join(', ')}\n" 
    h << "  Roles: #{roles.map(&:to_s).sort.join(', ')}\n" 
    h << "  Tasks:\n"
    tasks = self.tasks.map(&:to_s)
    tasks += roles.map { |r| r.tasks.map { |t| "    #{r}.#{t}" }}
    h << tasks.flatten!.sort!.join("\n")
  end

  # Returns an SSH::Gateway object for connecting to this host, or nil if no
  # gateway is needed.
  def tunnel
    if gw
      # We have a gateway host.
      @tunnel ||= gw.gateway_tunnel
    end
  end

  # Upload a file to the server. Remote defaults to local's filename (without
  # path) if not specified.
  def upload(local, remote = nil, opts={})
    remote ||= File.split(local).last
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
