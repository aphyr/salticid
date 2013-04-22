Salticid
=====

<a href="http://www.flickr.com/photos/robertwhyte/8034414631/" title="Salticidae Maratus sp. by Robert Whyte www.arachne.org.au, on Flickr"><img src="http://farm9.staticflickr.com/8034/8034414631_1d7906ac5d_b.jpg" width="850" height="674" alt="Salticidae Maratus sp."></a>

Salticidae is the family of jumping spiders: small, nimble, and quite
intelligent within a limited domain.

<img src="http://aphyr.com/media/salticid.png" width="100%" alt="Salticid installing riak" />

Salticid runs commands on other computers via SSH, with just enough
programmability and structure to run small-scale (~10-20 nodes in parallel)
deployments. It relies on horrifyingly evil ruby metaprogramming to provide a
small DSL which looks a bit like a shell.

```sh
gem install salticid
```

```ruby
# example.rb
host 'my_machine.com' do
  user 'my_username'

  task :hello do
    exec! 'ls -la /', echo: true
  end
end
```

```sh
salticid -l example.rb -h my_machine hello
```

Salticid will ssh to my_machine (you'll want your SSH agent to have your
credentials cached) and run the `hello` task, which lists the root directory
and echoes it to the console. If you don't have a remote node available, you
could always use `host 'localhost'`. Hit q to quit the ncurses interface when
you're satisfied.

We don't have to use fully qualified paths. Salticid hosts have a state machine which tracks the current directory:

```ruby
host 'my_machine.com' do
  user 'my_username'

  task :hello do
    cd '/'
    cd 'tmp'
    log "Now in directory", cwd
    exec! 'ls -la /', echo: true
  end
end
```

You can scroll using the arrow keys, or pgup/pgdn. If you don't like q, you can
always leave via Control+C, too. Sometimes salticid doesn't shut down actively
running processes properly: ^C will make sure they quit.

Some commands are built into lib/salticid/host.rb. Any ruby code you write
inside a task is instance_eval'd inside a Host object, so you have access to
any methods there. Any unrecognized methods will be intrepreted as shell
commands (or possibly as roles or tasks; we'll get to that later). So we can
replace exec! with:

```ruby
host 'my_machine.com' do
  user 'my_username'

  task :hello do
    ls '-la', '/', echo: true
  end
end
```

Salticid will escape any strings you pass this way. `cat 'foo bar'` in ruby
will turn into the shell command `cat "foo bar"`. `exec!` doesn't escape its
string: `exec! 'cat foo bar'` turns into the shell command `cat foo bar`. You
can always use `escape("some string")` if you need to do your own escaping.

Salticid functions return whatever the process printed to stdout, so it's easy
to get information from the remote system, massage it in Ruby, and use it in
your program:

```ruby
host 'my_machine.com' do
  user 'my_username'

  task :hello do
    my_username = whoami
    log "I am #{my_username.inspect}"
  end
end
```

The bar at the top of the interface turns green when the task completes
successfully, or red if it fails. Salticid checks the exit status of every
command, and throws an exception if it's non-zero:

```ruby
host 'my_machine.com' do
  user 'my_username'

  task :hello do
    cat '/frobnitz'
  end
end
```

Salticid logs the command which failed, the exit status, and the processes'
stderr and stdout. Now you can use Ruby's exception handling techniques to
write more complex tasks:

```ruby
host 'my_machine.com' do
  user 'my_username'

  task :hello do
    x = begin
          cat '/frobnitz' 
        rescue
          :purple
        end
    log "Got #{x}"
  end
end
```

Salticid is asynchronous, and you can register handlers to process stderr and
stdout interactively, or echo it to the interface as lines arrive:

```ruby
task :tail do
  tail '-F', '/var/log/syslog', echo: true
end
```

This one you have to kill with ^C.

You can redirect to a file with the `:to` argument, and send stdin to a process using `:stdin`:

```ruby
echo :stdin 'hallo', to: '/tmp/salutations'
```

Become a different user for the scope of a block:

```ruby
sudo do
  shutdown '-h', :now
end

sudo :postgres do
  createdb :omghai2u
end
```

Upload and download files (you probably want to check the source: these do some
helpful but non-obvious things)

```ruby
# Remote path, local path:
download '/etc/passwd', 'omghax.txt'
```

`__DIR__` is the directory the current file is in, so it's easy to keep scripts
and their related data files together. `/` combines path fragments. Pretty much
anywhere in Salticid, you can treat symbols and strings interchangeably.

```ruby
echo File.read(__DIR__/:riak/'app.config'),
     to: '/opt/riak/rel/riak/etc/app.config'
```

Often, you want to replace a file while preserving its ownership and mode:

```ruby
sudo_upload __DIR__/'apache.conf', '/etc/apache2/apache.conf'
```

Higher-level structure
---

You can group related tasks together into a role, and invoke tasks from each
other to bundle together dependencies:

```ruby
role :riak do
  task :start do
    sudo do
      cd '/opt/riak/rel/riak'
      exec! 'bash -c "ulimit -n 10000 && bin/riak start"', echo: true
    end
  end

  task :restart do
    sudo do
      cd '/opt/riak/rel/riak'
      exec! 'bin/riak start', echo: true
    end
  end

  task :stop do
    sudo do
      cd '/opt/riak/rel/riak'
      exec! 'bin/riak stop', echo: true
    end
  end

  task :ping do
    sudo do
      exec! '/opt/riak/rel/riak/bin/riak ping', echo: true
    end
  end

  task :deploy do
    sudo do
      riak.stop
      echo File.read(__DIR__/:riak/'app.config'), to: '/opt/riak/rel/riak/etc/app.config'
      echo File.read(__DIR__/:riak/'vm.args').gsub('%%NODE%%', name), to: '/opt/riak/rel/riak/etc/vm.args'
    end
    riak.start
  end
end
```

You can assign hosts to roles individually:

```ruby
host 'my-host' do
  role :riak
  role :postgres
end
```

And hosts can be bound together into groups:

```ruby
group :texas do
  host :n1
  host :n2
  host :n3
  host :n4

  each_host do
    user :deploy

    # You can assign instance variables to hosts to keep track of state.
    # @password is used by sudo and friends: 
    @password = "sup"

    # We can add roles and tasks here too:
    role :riak
    role :postgres
  end
end
```

Use `salticid -s salticid` to show all the groups, roles, hosts, and top-level
tasks defined. You can run a task only on hosts belonging to a role, group, or a specific host with -r, -g, and -h respectively; or on all appropriate hosts by default:

```sh
# Runs the deploy task in the riak role, on every host which has the riak role.
salticid riak.deploy
```

Salticid parallelizes across hosts. Use the left and right arrow keys, or tab,
to switch between hosts in the ncurses interface.

Typically you'll use salticid with a common set of files over and over again, instead of loading files explicitly with `-l`. You can put any commands to source in `~/.salticidrc`; they'll be evaluated on the top-level salticid context:

```ruby
load ENV['HOME'] + '/my-deploy/salticid/*.rb'
```

`load` can be used to load files in any salticid context. It obeys shell glob
expansion.

An example
---

Take a look at Jepsen's salticid config:
https://github.com/aphyr/jepsen/blob/master/salticid/main.rb

Caveats
---

Salticid starts to get unresponsive or flaky above 10 or 20 nodes in parallel. There's no reason the interface and scheduler can't execute tasks in small chunks instead of all at once; I just never needed the feature so I didn't write it.

Salticid's ncurses interface is a little flaky/slow. It doesn't scroll
line-wise very well.

Salticid is *not* a cloud deployment system, though you could dynamically
create hosts to make it into one. As presented here, it's designed for fixed
sets of nodes. We used it at Showyou and Vodpod to manage ~30 physical nodes in
two datacenters.

Salticid has no central control of deployment. There is no server or locking.
There is nothing to install. All you need is SSH. Anyone with credentials can
use it, which makes it ideal for scenarios when you don't have control over the
entire infrastructure but still need to automate some tasks. We had a small
team and kept our config in a git repo, and added a ruby check to verify the
repo was up to date before running any commands. All is anarchy.

This is not a config management tool. It has no notion of convergence or
scheduled checks, and can't tell you when things are out of sync with a target.
On the other hand, it runs at interactive latencies and tells you what went
wrong immediately, so you may find keeping systems up to date is easier with
Salticid. I strongly recommend writing idempotent tasks so you can just re-run
them whenever you make a change or want to confirm everything is in order.

`apt-get -y` is your friend. :)

Advanced
---

Salticid can tunnel its connections through an intermediate SSH gateway node. I
like to give each user a distinct user account on the gateway and a special key
for the gateway, and share a single deploy account/keypair for everything
*behind* the gateway; makes it fast and easy to revoke a pubkey for a specific
user if their laptop is stolen, without having to touch every machine.

```
gw 'gw.mycorp.com' do
  user ENV['USER']
end

[1,2,3,4,5].each do |i|
  host "db#{i}" do
    gw 'gw.mycorp.com'
    user :deploy
    role :ubuntu
    role :riak
  end
end
``` 

You can break out of Salticid at any point, which is useful if you don't want
the full interface:

```ruby
task :console do
  Hydra::Interface.shutdown false

  if tunnel
    tunnel.open(name, 22) do |port|
      system "ssh #{user}@localhost -p #{port}"
    end
  else
    system "ssh #{user}@#{name}"
  end
end
```

Now `hydra -h my.host.com console` will drop you into an SSH console on that
node.

History
---

Salticid is a deployment tool I wrote for Vodpod and Showyou in a couple of weekends. Its only design goals were:

1. Magic
2. More Magic

It violates every principle of good software development possible. It is clunky, slow, buggy, and dangerous.

It also worked surprisingly well. YMMV. d=('_~)=b
