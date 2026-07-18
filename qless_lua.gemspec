# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'qless_lua'
  spec.version       = '1.2.0'
  spec.authors       = ['Anton Baklanov']
  spec.email         = ['antonbaklanov@gmail.com']

  spec.summary       = 'Lua scripts for the Qless job queue system'
  spec.description   = 'Core Lua scripts that power the Qless job queue system, packaged as a Ruby gem'
  spec.homepage      = 'https://github.com/libqless/qless-core'
  spec.license       = 'MIT'

  spec.metadata = {
    'source_code_uri' => 'https://github.com/libqless/qless-core',
    'changelog_uri'   => 'https://github.com/libqless/qless-core/blob/master/changes.md',
  }

  spec.files = Dir[
    'ruby/lib/*.rb',
    'dist/*.lua',
    'qless_lua.gemspec',
  ]

  spec.require_paths = ['ruby/lib']

  spec.required_ruby_version = '>= 2.7.0'
end
