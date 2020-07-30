# Process

![Build Status - Cirrus][]

A process runner for Dart that uses the
[`ProcessManager`](https://github.com/google/process.dart/blob/master/lib/src/interface/process_manager.dart#L21)
class from [`package:process`](https://pub.dev/packages/process), and manages
the stderr and stdout properly so that you don't lose any output.

Like `dart:io` and `package:process`, it supplies a rich, Dart-idiomatic API for
spawning OS processes, with the added benefit of easy retrieval of stdout and
stderr from the result of running the process, with proper waiting for the
process and stderr/stdout streams to be closed.

In addition to being able to launch processes separately, it allows creation of
a pool of worker processes, and manages running them with a set number of active
processes, and manages collection of their stdout, stderr, and interleaved
stdout and stderr.

See the [example](example/) for more information on how to use it, but the basic
usage for [`ProcessRunner`](lib/process_runner_impl.dart) is:

```dart
ProcessRunnerResult result = await processRunner.runProcess(['command', 'arg1', 'arg2']);
// Print stdout:
print(result.stdout);
// Print stderr:
print(result.stderr);
// Print interleaved stdout/stderr:
print(result.output);
```

For the [`ProcessPool`](lib/process_pool.dart), also see the [example](example), but it basically looks like this:

```dart
  ProcessPool pool = ProcessPool(numWorkers: 2);
  final List<WorkerJob> jobs = <WorkerJob>[
    WorkerJob('Job 1', ['command1', 'arg1', 'arg2']),
    WorkerJob('Job 2', ['command2', 'arg1']),
  ];
  await for (final WorkerJob job in pool.startWorkers(jobs)) {
    print('\nFinished job ${job.name}');
  }
```

[Build Status - Cirrus]: https://api.cirrus-ci.com/github/google/process_runner.svg
