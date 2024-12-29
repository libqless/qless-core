#!/usr/bin/env ruby

require 'erb'

dir = File.dirname(__FILE__)

qless_lua_source = File.read("#{dir}/../dist/qless.lua")
template = File.read("#{dir}/lib/qless_lua.rb.erb")

erb = ERB.new(template)

puts erb.result(binding)
