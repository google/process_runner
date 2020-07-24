# Process

[![Build Status -](https://travis-ci.org/google/process_runner.svg?branch=master)](https://travis-ci.org/google/process_runner)
[![Coverage Status -](https://coveralls.io/repos/github/google/process_runner/badge.svg?branch=master)](https://coveralls.io/github/google/process_runner?branch=master)

A process runner for Dart that wraps the `Process` class from `dart:io`, and manages the stderr and stdout properly so that you don't lose any output.

Like `dart:io` and `package:process`, it supplies a rich, Dart-idiomatic API for
spawning OS processes.

In addition to being able to launch processes separately, it allows creation of a queue of worker processes, and manages running them with a set number of active processes, and manages collection of their stdout, stderr, and interleaved stdout and stderr.

See the [example](example/) for more information on how to use it.