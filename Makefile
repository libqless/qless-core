all: dist/qless.lua ruby

dist/qless-lib.lua: src/*.lua
	cat src/base.lua \
	    src/config.lua \
		src/job.lua \
		src/queue.lua \
		src/recurring.lua \
		src/worker.lua > dist/qless-lib.lua

dist/qless.lua: dist/qless-lib.lua src/api.lua
	cat dist/qless-lib.lua src/api.lua | \
		egrep -v '^[[:space:]]*--[^\[]' | \
		egrep -v '^--$$' > dist/qless.lua

.PHONY: clean test ruby gem
clean:
	rm -rf dist/qless.lua dist/qless-lib.lua ruby/lib/qless_lua.rb

test: dist/qless.lua
	py.test

ruby: dist/qless.lua
	./ruby/generate.rb > ruby/lib/qless_lua.rb

gem: ruby
	cd ruby && gem build qless_lua.gemspec
