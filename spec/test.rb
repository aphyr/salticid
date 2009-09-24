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
end
