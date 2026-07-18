# Qless Core

A maintained fork of [seomoz/qless-core](https://github.com/seomoz/qless-core),
which is no longer actively developed.

`qless-core` is the set of Lua scripts that implement the [Qless](https://github.com/seomoz/qless)
job queue. All of the queue logic (put, pop, complete, fail, heartbeat,
recurring jobs, stats, dependencies, tags, tracking) runs server-side inside
Redis via `EVAL`, so operations are atomic. Language bindings are thin clients
that register this script and call commands on it.

## What's different in this fork

- **Redis / Valkey compatibility** — fixes for newer Redis versions and
  continuous testing against a broad matrix (Redis 5 through 8.2, Valkey
  7.2 through 8.1).
- **Recreated test environment** — the test suite was cleaned up, ported to
  Python 3 / current `pytest` and `redis`, and made easy to run locally via
  Docker Compose.
- **CI via GitHub Actions** — every push runs `make clean all`, verifies the
  built `dist/` is committed and in sync with `src/`, and runs the full suite
  across the Redis/Valkey matrix.
- **Ruby gem packaging** — the built scripts ship as the `qless_lua` gem for
  easy consumption from Ruby projects.

## Build

Source lives in `src/*.lua` as separate modules; the shipped artifacts in
`dist/` are those modules concatenated in a fixed order with comments stripped.
**Never edit `dist/*.lua` directly — edit `src/*.lua` and rebuild.** The built
`dist/` files are committed and must stay in sync with `src/`.

```bash
make                     # build dist/qless.lua (default)
make clean all           # rebuild from scratch
make dist/qless-lib.lua  # core classes only, no API dispatch wrapper (for composition)
```

## Test

Tests are written in Python (pytest) and run against a real Redis. Rebuild
`dist/` before testing.

```bash
pip install -r requirements.txt
make test                                # against localhost:6379
REDIS_URL='redis://host:port' make test  # non-default Redis location
py.test test/test_queue.py               # a single file
py.test test/test_queue.py -k test_pop   # a single test
```

Or use Docker Compose to get a Python container plus a healthy Redis with
`REDIS_URL` preset:

```bash
docker compose run --rm shell
# then, inside the container:
pip install -r requirements.txt && make test
```

## Ruby gem

The built Lua scripts are packaged as the `qless_lua` gem, which exposes
`QlessLua::QLESS_SOURCE` and `QlessLua::QLESS_LIB_SOURCE`.

```bash
make gem   # gem build qless_lua.gemspec
```

Bump `spec.version` in `qless_lua.gemspec` for releases.

## Architecture

For the object model, conventions, features, configuration options, and the
internal Redis data structures, see [ARCHITECTURE.md](ARCHITECTURE.md).
