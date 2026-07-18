# Qless Core Architecture

This document describes the internals of `qless-core`: the conventions the code
follows, the features it provides, its configuration options, and the internal
Redis data structures it maintains. For build/test/usage instructions see the
[README](README.md).

## Modules

The unified `qless.lua` script is developed as several smaller submodules under
`src/`, concatenated together at build time (see the `Makefile`):

- `base.lua` — forward declarations and some uncategorized functions
- `config.lua` — all configuration interactions
- `job.lua` — the regular job class
- `queue.lua` — the queue class
- `recurring.lua` — the recurring job class
- `worker.lua` — manage available workers
- `api.lua` — exposes the interfaces that the clients invoke; a very thin
  wrapper around these classes

`dist/qless-lib.lua` is everything except `api.lua`, so you can build on top of
the qless core library **within your own lua scripts** through composition.

## Conventions

### No `KEYS`

The scripts do not use the `KEYS` portion of the Redis Lua API. For just about
all operations there's no way to determine a priori which Redis keys will be
touched, so qless passes everything through `ARGV` instead. The script asserts
that `#KEYS == 0`.

### Time, time everywhere

To ease the client logic, every command takes a timestamp with it. In many
cases this argument is ignored, but it is still required in order to make a
valid call. This requirement only comes through in the exposed script API, not
in the class interface — at the class-function level, only the functions which
require the `now` argument list it.

### Documentation

The documentation of the code is present in each of the modules under `src/`,
but it is excluded from the built `dist/` scripts to reduce their weight.

## Features and Philosophy

### Locking

A worker is given an exclusive lock on a piece of work when it is given that
piece of work. That lock may be renewed periodically so long as it's before the
provided 'heartbeat' timestamp. Likewise, it may be completed.

If a worker attempts to heartbeat a job, it may optionally provide an updated
JSON blob to describe the job. If the job has been given to another worker, the
heartbeat should return `false` and the worker should yield.

When a node attempts to heartbeat, the script checks to see if the node
attempting to renew the lock is the same node that currently owns the lock. If
so, then the lock's expiration is pushed back accordingly and the updated
expiration returned. If not, an exception is raised.

### Stats

Qless collects statistics for job wait time (time popped − time put) and job
completion time (time completed − time popped). By 'statistics' we mean average,
variance, count and a histogram. Stats for the number of failures and retries
for a given queue are also available.

Stats are grouped by day. In the case of job wait time, its stats are
aggregated on the day when the job was popped. In the case of completion time,
they are grouped by the day it was completed.

### Tracking

Jobs can be tracked, which just means that they are accessible and displayable.
This can be useful if you just want to keep tabs on the progress of jobs through
the pipeline. All the currently-tracked jobs are stored in a sorted set,
`ql:tracked`.

### Failures

Failures are stored in such a way that we can quickly summarize the number of
failures of a given type, but also which items have succumbed to that type of
failure. There is a Redis set, `ql:failures`, whose members are the names of the
various failure lists. Each type of failure then has its own list of instance
ids that encountered such a failure. For example:

```
ql:failures
=============
upload error
widget failure

ql:f:upload error
==================
deadbeef
...
```

### Worker data

A sorted set of workers, sorted by the last time they had any activity, is kept
at `ql:workers`.

In addition, the set of jids that a worker currently has locks for is kept at
`ql:w:<worker>:jobs`, sorted by the time when we last saw a heartbeat (or pop)
for that worker from that job.

### Job data deletion

Data about completed jobs is pruned periodically, both by the maximum number of
retained completed jobs and by the maximum age for retained jobs. A sorted set
at `ql:completed` keeps track of which items should be expired.

## Configuration Options

Configuration is stored in the key `ql:config`. Supported options:

1. `heartbeat` (60) — the default heartbeat in seconds for queues
1. `stats-history` (30) — the number of days to store summary stats
1. `histogram-history` (7) — the number of days to store histogram data
1. `jobs-history-count` (50k) — how many jobs to keep data for after they're
   completed
1. `jobs-history` (604800 — 7 days in seconds) — how many seconds to keep jobs
   after they're completed
1. `<queue name>-heartbeat` — the heartbeat interval (in seconds) for a
   particular queue
1. `max-worker-age` (86400) — how long before workers are considered disappeared
1. `<queue>-max-concurrency` — the maximum number of jobs that can be running in
   a queue. If this number is reduced, it does not impact any currently-running
   jobs
1. `max-job-history` (100) — the maximum number of items in a job's history.
   This can be used to help control the size of long-running jobs' history

## Internal Redis Structure

This section describes the internal structure and naming conventions. The `ql:`
namespace prefixes every key.

### Jobs

Each job is stored primarily in a key `ql:j:<jid>`, a Redis hash, which contains
most of the keys that describe the job. A set (possibly empty) of jids on which
this job depends is stored in `ql:j:<jid>-dependencies`. A set (also possibly
empty) of jids that rely on the completion of this job is stored in
`ql:j:<jid>-dependents`. For example, `ql:j:<jid>`:

```
{
	# This is the same id as identifies it in the key. It should be
	# a hex value of a uuid
	'jid'         : 'deadbeef...',

	# This is a 'type' identifier. Clients may choose to ignore it,
	# or use it as a language-specific identifier for determining
	# what code to run. For instance, it might be 'foo.bar.FooJob'
	'type'        : '...',

	# This is the priority of the job -- lower means more priority.
	# The default is 0
	'priority'    : 0,

	# This is the user data associated with the job. (JSON blob)
	'data'        : '{"hello": "how are you"}',

	# A JSON array of tags associated with this job
	'tags'        : '["testing", "experimental"]',

	# The worker ID of the worker that owns it. Currently the worker
	# id is <hostname>-<pid>
	'worker'      : 'ec2-...-4925',

	# This is the time when it must next check in
	'expires'     : 1352375209,

	# The current state of the job: 'waiting', 'pending', 'complete'
	'state'       : 'waiting',

	# The queue that it's associated with. 'null' if complete
	'queue'       : 'example',

	# The maximum number of retries this job is allowed per queue
	'retries'     : 3,
	# The number of retries remaining
	'remaining'   : 3,

	# The jids that depend on this job's completion
	'dependents'  : [...],
	# The jids that this job is dependent upon
	'dependencies': [...],

	# A list of all the things that have happened to a job. Each entry has
	# the keys 'what' and 'when', but it may also have arbitrary keys
	# associated with it.
	'history'   : [
		{
			'what'  : 'Popped',
			'when'  : 1352075209,
			...
		}, {
			...
		}
	]
}
```

### Queues

A queue is a priority queue and consists of several sorted sets, keyed by
`ql:q:<name>-<group>`:

1. `ql:q:<name>-scheduled` — sorted set of all scheduled job ids
1. `ql:q:<name>-work` — sorted set (by priority) of all jobs waiting
1. `ql:q:<name>-locks` — sorted set of job locks and expirations
1. `ql:q:<name>-depends` — sorted set of jobs in a queue, but waiting on other
   jobs

When looking for a unit of work, the client first chooses from the next expired
lock. If none are expired, then any jobs that should now be considered eligible
(the scheduled time is in the past) are inserted into the work queue. A sorted
set of all the known queues is maintained at `ql:queues`.

When a job is completed, it removes itself as a dependency of all the jobs that
depend on it. If it was the last job that a job depended on, that job is then
inserted into the queue's work.

### Stats

Stats are grouped by day and queue. The day portion of the stats key is an
integer timestamp of midnight for that day:

```
<day> = time - (time % (24 * 60 * 60))
```

Wait- and run-time stats are stored under two hashes, `ql:s:wait:<day>:<queue>`
and `ql:s:run:<day>:<queue>`, each with the keys:

- `total` — the total number of data points contained
- `mean` — the current mean value
- `vk` — not the actual variance, but a number that can be used to both
  numerically stably find the variance and compute it in a
  [streaming fashion](http://www.johndcook.com/standard_deviation.html)
- `s1`, `s2`, ... — second-resolution histogram counts for the first minute
- `m1`, `m2`, ... — minute-resolution for the first hour
- `h1`, `h2`, ... — hour-resolution for the first day
- `d1`, `d2`, ... — day-resolution for the rest

There is also a hash, `ql:s:stats:<day>:<queue>`, with keys:

- `failures` — how many failures there have been. If a job is run twice and
  fails repeatedly, this is incremented twice.
- `failed` — how many are currently failed
- `retries` — how many jobs we've had to retry

### Tags

All jobs store a JSON array of the tags that are associated with them. In
addition, the keys `ql:t:<tag>` store a sorted set of all the jobs associated
with that particular tag. The score of each jid in that tag is the time when
that tag was added to that job. When jobs are tagged a second time with an
existing tag, it's a no-op.

## Implementing Clients

There are a few nuanced aspects of implementing bindings for your particular
language that are worth bringing up. The canonical examples for bindings are the
[python](https://github.com/seomoz/qless-py) and
[ruby](https://github.com/seomoz/qless) bindings.

### Testing

The majority of tests are implemented in `qless-core`, and so your bindings
should merely test that they provide sensible access to the functionality. This
should include a notion of `queues`, `workers`, `jobs`, etc.

### Running the worker

If your language supports dynamic importing of code, and in particular if a
class can be imported deterministically from a string identifier, then you
should include a worker executable with your release. For example, in Python,
given the class `foo.Job`, that string is enough to know what module to import.
A worker binary can just be given a list of queues, a number (and perhaps type)
of workers, wait intervals, etc., and then import all the code required to
perform work.

### Timestamps

Jobs with identical priorities are popped in the order they were inserted. The
caveat is that it's only true to the precision of the timestamps your bindings
provide. For example, if you provide timestamps to the second granularity, then
jobs with the same priority inserted in the same second can be popped in any
order. Timestamps at the thousandths-of-a-second granularity will maintain this
property better.

### Filesystem access

It's intended to be a common use case that bindings provide a worker script or
binary that runs several worker subprocesses. These should run with their
working directory as a sandbox.

### Forking model

There are a couple of philosophies regarding how to best fork processes to do
work. Certainly, there should be a parent process that manages child processes.
We encourage you to make all models available in your client:

- **Fork once for each job** — this has the added benefit of containing
  potential issues like resource leaks, but it comes at the potentially high
  cost of forking once for each job.
- **Fork long-running processes** — forking long-running processes means that
  you will likely be able to saturate the CPUs on a machine more easily, and
  reduces the cost per job of forking.
- **Coroutines in long-running processes** — especially for I/O-bound processes
  this is handy, since you can keep the number of processes relatively small and
  still get good I/O parallelism.

Each style of worker should be able to listen for worker-specific `lock_lost`,
`canceled` and `put` events, each of which can signal that a worker has lost its
right to process a job.

### Queue popping order

Workers are allowed (and encouraged) to pop off of more than one queue. Workers
should support two modes of popping: ordered and round-robin. Consider queues
`A`, `B`, and `C` with job counts:

    A: 5
    B: 2
    C: 3

In an ordered version, the order in which the queues are specified has
significance in the order in which jobs are popped. For example, if our queues
were ordered `C, B, A` in the worker, we'd pop jobs off:

    C, C, C, B, B, A, A, A, A, A

In the round-robin implementation, a worker pops off a job from each queue as it
progresses through all queues:

    C, B, A, C, B, A, C, A, A, A

## Internal Style Guide

These aren't meant to be stringent, but just to keep the code formatted
similarly so that the same variable names have the same meaning throughout.

1. Parameter sanitization should be performed as early as possible. This
   includes making use of `assert` and `error` based on the number and type of
   arguments.
1. Job ids should be referred to as `jid`, both internally and in the clients.
1. Failure types should be described with `group`.
1. Job types should be described as `klass` (nod to Resque), because both 'type'
   and 'class' are commonly used in languages.
