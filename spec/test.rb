#!/usr/bin/env ruby

require 'rubygems'
require 'bacon'
require File.expand_path "#{File.dirname(__FILE__)}/../lib/salticid"


describe "A Host" do
  @h = Salticid.new
  @h.host :localhost do
    user ENV['USER']
  end
 
  should 'start in /' do
    @h.host :localhost do
      pwd.should === '/'
    end
  end

  should 'know home directories' do
    @h.host :localhost do
      homedir.should == ENV['HOME']
    end
  end

  should 'change directories' do
    @h.host :localhost do
      cd '/tmp'
      pwd.should === '/tmp'
      cd
      pwd.should === ENV['HOME']
    end
  end

  should 'run programs' do
    @h.host :localhost do
      date.should =~ /\d\d:\d\d:\d\d/
    end
  end

  should 'test file types' do
    @h.host :localhost do
      cd '/tmp'
      dir?('.').should == true
      file?('.').should == false

      rm 'foo' rescue nil

      exists?('foo').should == false
      file?('foo').should == false
      dir?('foo').should == false

      touch 'foo'
      file?('foo').should == true
      exists?('foo').should == true
      dir?('foo').should == false

      rm 'foo'
    end
  end
 
  should 'read file modes' do
    @h.host :localhost do
      mode(ENV['HOME']).should == File.stat(ENV['HOME']).mode & 07777
    end
  end

  should 'accept standard input' do
    @h.host :localhost do
      cd '/tmp'
      cat(:stdin => 'foo').should == 'foo'
      tee 'foo.log', :stdin => 'hey this is some standard input'
      cat('foo.log').should == 'hey this is some standard input'
      rm 'foo.log'
    end
  end
 
  should 'append to files' do
    @h.host :localhost do
      cd '/tmp'
      exec! 'echo foo > salticid_tmp'
      append('bar', 'salticid_tmp')
      cat('salticid_tmp').should == "foo\nbar"

      append('bar', 'salticid_tmp', :uniq => true)
      cat('salticid_tmp').should == "foo\nbar"

      rm 'salticid_tmp'
    end
  end

  should 'run as different users via sudo' do
    @h.host :localhost do
      as ENV['USER'] do
        cd '/tmp'
        pwd.should == '/tmp'
        exec! 'echo foo > salticid_tmp'
        cat('salticid_tmp').should == "foo"
        rm 'salticid_tmp'
      end
    end
  end

  should 'tail a log file' do
    @h.host :localhost do
      i = 0
      out = tail('-f', '/var/log/syslog', :stdout => lambda {i += 1}) do |ch|
        sleep 3
        ch.close
      end
      i.should > 1
      out.should.not.be.empty
    end
  end

  should 'redirect output' do
    @h.host :localhost do
      rm '/tmp/salticid_tmp' if exists? '/tmp/salticid_tmp'
      cat :stdin => 'foo', :to => '/tmp/salticid_tmp'
      cat('/tmp/salticid_tmp').should == 'foo'
      rm '/tmp/salticid_tmp'
    end
  end
end
