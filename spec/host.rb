#!/usr/bin/env ruby

require 'rubygems'
require 'bacon'
require "#{File.dirname(__FILE__)}/../lib/hydra"

describe "A Host" do
  @h = Hydra.new

  @h.role :awesome do
    task :setup do
      'awesome setup'
    end
  end

  @h.role :dreary do
    task :setup do
      'dreary setup'
    end
  end

  @h.host :localhost do
    user ENV['USER']
    role :awesome
    role :dreary
  end

  should 'resolve tasks in roles' do
    @h.host :localhost do
      awesome.setup.should == 'awesome setup'
      dreary.setup.should == 'dreary setup'
      lambda { setup }.should.raise
    end
  end
end
