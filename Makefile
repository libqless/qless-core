all: qless.lua qless-lib.lua

qless-lib.lua: src/base.lua src/config.lua src/job.lua src/queue.lua src/recurring.lua src/worker.lua
	echo "-- Current SHA: `git rev-parse HEAD`" > qless-lib.lua
	echo "-- This is a generated file" >> qless-lib.lua
	cat src/base.lua src/config.lua src/job.lua src/queue.lua src/recurring.lua src/worker.lua >> qless-lib.lua

qless.lua: qless-lib.lua src/api.lua
	# Cat these files out, but remove all the comments from the source
	echo "-- Current SHA: `git rev-parse HEAD`" > qless.lua
	echo "-- This is a generated file" >> qless.lua
	cat qless-lib.lua src/api.lua | \
		egrep -v '^[[:space:]]*--[^\[]' | \
		egrep -v '^--$$' >> qless.lua

.PHONY: clean test 
clean:
	rm -rf qless.lua qless-lib.lua 

test: qless.lua
	py.test