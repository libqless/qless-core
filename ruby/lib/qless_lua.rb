# frozen_string_literal: true

# Lua scripts for the Qless job queue system.
class QlessLua
  LUA_DIR = File.expand_path('../../dist', __dir__)

  class << self
    def qless_source
      @qless_source ||= read_lua('qless.lua')
    end

    def qless_lib_source
      @qless_lib_source ||= read_lua('qless-lib.lua')
    end

    def const_missing(name)
      case name
      when :QLESS_SOURCE
        const_set(:QLESS_SOURCE, qless_source)
      when :QLESS_LIB_SOURCE
        const_set(:QLESS_LIB_SOURCE, qless_lib_source)
      else
        super
      end
    end

  private

    def read_lua(name)
      File.read(File.join(LUA_DIR, name))
    end
  end
end
