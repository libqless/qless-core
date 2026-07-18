all: dist/qless.lua

dist/qless-lib.lua: src/*.lua
	cat src/base.lua \
	    src/config.lua \
		src/job.lua \
		src/queue.lua \
		src/recurring.lua \
		src/worker.lua | \
		egrep -v '^[[:space:]]*--[^\[]' | \
		egrep -v '^--$$' > dist/qless-lib.lua

dist/qless.lua: dist/qless-lib.lua src/api.lua
	cat dist/qless-lib.lua src/api.lua | \
		egrep -v '^[[:space:]]*--[^\[]' | \
		egrep -v '^--$$' > dist/qless.lua

.PHONY: clean test gem
clean:
	rm -rf dist/qless.lua dist/qless-lib.lua

test: dist/qless.lua
	py.test

gem: dist/qless.lua
	gem build qless_lua.gemspec
