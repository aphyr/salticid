#!/usr/bin/env ruby

require 'rubygems'
require 'bacon'
require "#{File.dirname(__FILE__)}/../lib/hydra"


describe "A Host" do
  @h = Hydra.new
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
      exec! 'echo foo > hydra_tmp'
      append('bar', 'hydra_tmp')
      cat('hydra_tmp').should == "foo\nbar"

      append('bar', 'hydra_tmp', :uniq => true)
      cat('hydra_tmp').should == "foo\nbar"

      rm 'hydra_tmp'
    end
  end

  should 'run as different users via sudo' do
    @h.host :localhost do
      as ENV['USER'] do
        cd '/tmp'
        pwd.should == '/tmp'
        exec! 'echo foo > hydra_tmp'
        cat('hydra_tmp').should == "foo"
        rm 'hydra_tmp'
      end
    end
  end
end
