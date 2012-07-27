#!/usr/bin/env ruby

require 'rubygems'
require 'bacon'
require File.expand_path "#{File.dirname(__FILE__)}/../lib/salticid"

describe "Groups" do
  @h = Salticid.new

  @h.host :foo do
  end

  @h.group :top do
    group :sub do
      host :foo
    end
  end

  @h.host :bar do
    group :top
  end

  @h.host :baz do
    group @salticid.top.sub
  end

  it 'should resolve top-level groups' do
    @h.top.should.be.kind_of? Salticid::Group
  end

  it 'should resolve nested groups' do
    @h.top.sub.should.be.kind_of? Salticid::Group
  end

  it 'should nest groups' do
    @h.groups.should.not.include? @h.top.sub
    @h.top.groups.should.include? @h.top.sub
  end
  
  it 'groups should specify hosts' do
    @h.top.sub.hosts.should.include? @h.host(:foo)
    @h.host(:foo).groups.should.include? @h.top.sub
  end

  it 'hosts should specify top-level groups by name' do
    @h.host(:bar).groups.should.include? @h.top
    @h.top.hosts.should.include? @h.host(:bar)
  end

  it 'hosts should specify nested groups' do
    @h.host(:baz).groups.should.include? @h.top.sub
    @h.top.sub.hosts.should.include? @h.host(:baz)
  end

  it 'groups should include all nested hosts' do
    @h.top.hosts.should.include? @h.host(:foo)
    @h.top.hosts.should.include? @h.host(:bar)
    @h.top.hosts.should.include? @h.host(:baz)
  end
end
