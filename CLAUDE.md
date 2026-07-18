# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`qless-core` is the set of Lua scripts implementing the Qless job queue, executed inside Redis via `EVAL`. All of Qless's queue logic (put, pop, complete, fail, heartbeat, recurring jobs, stats, dependencies, tags, tracking) lives here as server-side Lua so that operations are atomic. Language bindings (qless-py, qless-rb, etc.) are thin clients that register this script and call commands on it.

This fork also packages the built scripts as a Ruby gem (`qless_lua`).

## Build

Source lives in `src/*.lua` as separate modules; the shipped artifacts in `dist/` are those modules concatenated in a fixed order with comment lines stripped out (via the `egrep` filters in the `Makefile`). **Never edit `dist/*.lua` directly — edit `src/*.lua` and rebuild.**

```bash
make            # builds dist/qless.lua (default target)
make clean all  # rebuild from scratch
make dist/qless-lib.lua   # core classes only, no API dispatch wrapper (for composition)
```

Concatenation order (defined in `Makefile`): `base → config → job → queue → recurring → worker`, then `api.lua` appended for the full `qless.lua`. Order matters — later modules depend on forward declarations in `base.lua`.

CI (`.github/workflows/test.yml`) runs `make clean all` then `git diff --exit-code`, so **`dist/` must be committed and in sync with `src/`**. Always rebuild and commit `dist/` after changing `src/`.

## Test

Tests are written in Python (pytest) and run against a real Redis. They register `dist/qless.lua` and invoke commands, asserting on return values and pub/sub events — so **rebuild `dist/` before testing**.

```bash
make test                                    # runs `py.test` (depends on dist/qless.lua)
pip install -r requirements.txt              # pytest + redis client
REDIS_URL='redis://host:port' make test      # non-default Redis location
py.test test/test_queue.py                   # single file
py.test test/test_queue.py -k test_pop       # single test by name
```

CI runs the suite against a matrix of Redis 5–8.2 and Valkey 7.2–8.1; keep Lua compatible across those versions.

### Docker

```bash
docker compose run --rm shell   # python container + healthy redis (REDIS_URL preset)
# then inside: pip install -r requirements.txt && make test
```

## Architecture

### Object model (src/)

The Lua is organized as OO-style tables with metatables, all forward-declared in `base.lua`:

- **`base.lua`** — the `Qless` root table (namespace `ql:`), forward declarations for `QlessQueue`/`QlessWorker`/`QlessJob`/`QlessRecurringJob`/`Qless.config`, shared helpers (`tbl_extend`, publish, etc.).
- **`config.lua`** — `Qless.config` get/set/unset with defaults.
- **`job.lua`** — `QlessJob`, the regular job lifecycle (state transitions, complete, fail, retry, heartbeat, depends, tag, track).
- **`queue.lua`** — `QlessQueue`, the priority-queue machinery (work/scheduled/locks/depends sorted sets, pop selection, stats recording).
- **`recurring.lua`** — `QlessRecurringJob`, cron-like job spawning.
- **`worker.lua`** — `QlessWorker`, worker registration/deregistration and worker→jobs tracking.
- **`api.lua`** — `QlessAPI` table: a thin string-keyed dispatch layer that the clients actually call. Each entry unpacks args and delegates to the classes above.

### Command dispatch (api.lua)

Every client call is one `EVAL` of `qless.lua` with **no `KEYS`** and `ARGV = [command_name, now, ...args]`:

- `KEYS` must be empty — the script asserts `#KEYS == 0`. Redis keys touched cannot be known a priori, so qless deliberately does not use `KEYS`.
- `ARGV[1]` is the command name (looked up in `QlessAPI`, e.g. `put`, `pop`, `complete`, `config.get`, `recur.tag`).
- `ARGV[2]` is `now`, a client-supplied timestamp (**required on every call** even when a given command ignores it). This is what keeps time deterministic and testable — tests pass explicit timestamps like `0`.

### Redis data model (namespace `ql:`)

Jobs at `ql:j:<jid>` (hash) plus `-dependencies`/`-dependents` sets. Queues split across `ql:q:<name>-work` / `-scheduled` / `-locks` / `-depends` sorted sets. Stats in `ql:s:wait:<day>:<queue>` and `ql:s:run:<day>:<queue>` (with streaming variance + histogram buckets `s#`/`m#`/`h#`/`d#`). Tags at `ql:t:<tag>`, failures at `ql:failures` + `ql:f:<group>`, workers at `ql:workers` + `ql:w:<worker>:jobs`, tracked jobs at `ql:tracked`. See README.md "Internal Redis Structure" for the full field-by-field layout.

### Events

Many operations `publish` to Redis pub/sub channels (`ql:log`, `ql:track`, `ql:canceled`, etc.). `test/test_events.py` asserts the exact event stream; the test harness (`test/qless.py`, `QlessRecorder`) captures pub/sub messages via the `with self.lua:` context manager.

## Test harness notes (test/)

- `common.py` — `TestQless` base class; `setUpClass` registers the script, `tearDown` flushes the DB. Also provides `assertMalformed` for asserting bad inputs raise `redis.ResponseError`.
- `qless.py` — `QlessRecorder`. `self.lua(cmd, now, ...)` JSON-encodes dict/list args, calls the script, and JSON-decodes the result. `with self.lua:` records published events into `self.lua.log`.
- Comments are stripped from `dist/` at build time, so documentation lives only in `src/`.

## Ruby gem packaging

`ruby/lib/qless_lua.rb` exposes `QlessLua::QLESS_SOURCE` / `QLESS_LIB_SOURCE` reading from `dist/*.lua`. Build with `make gem` (runs `gem build qless_lua.gemspec`); the gemspec ships `ruby/lib/*.rb` and `dist/*.lua`. Bump `spec.version` in `qless_lua.gemspec` for releases.
