#!/usr/bin/env ruby

require 'erb'

dir = File.dirname(__FILE__)

qless_lib_source = File.read("#{dir}/../dist/qless-lib.lua")
qless_source = File.read("#{dir}/../dist/qless.lua")

template = File.read("#{dir}/lib/qless_lua.rb.erb")

erb = ERB.new(template)

puts erb.result(binding)
