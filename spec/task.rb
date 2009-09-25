#!/usr/bin/env ruby

require 'rubygems'
require 'bacon'
require "#{File.dirname(__FILE__)}/../lib/hydra"


describe "Tasks" do
  @h = Hydra.new
  @h.host :localhost do
    user ENV['USER']
  end

  @h.task :task1 do
    name
  end

  should 'call tasks as methods' do
    @h.host :localhost do
      task :task1
      task1.should == 'localhost'
    end
  end

  should 'be able to set instance variables on hosts' do
    @h.task :setter do
      @somevar = :foo
    end

    @h.host :localhost do
      task :setter

      setter

      self.instance_variable_get('@somevar').should == :foo
    end
  end
end
