#!/usr/bin/env ruby

require 'rubygems'
require 'bacon'
require File.expand_path "#{File.dirname(__FILE__)}/../lib/salticid"


describe "Roles" do
  @h = Salticid.new
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
