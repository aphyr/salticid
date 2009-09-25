#!/usr/bin/env ruby

require 'rubygems'
require 'bacon'
require "#{File.dirname(__FILE__)}/../lib/hydra"


describe "Roles" do
  @h = Hydra.new
  @h.host :localhost do
    user ENV['USER']
  end

  should 'define methods on hosts' do
    @h.role :defined do
      define_method :foo do
        1
      end
    end

    puts @h.role(:define).methods.sort
  end
end
