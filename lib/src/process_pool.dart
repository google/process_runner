// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show Encoding;
import 'dart:io' show Directory, Platform, stdout, SystemEncoding, stderr, ProcessStartMode;

import 'package:async/async.dart' show StreamGroup;

import 'process_runner.dart';

/// Base class for all job types.
///
/// Defines an API for getting at the sub-tasks of a job, and for getting the
/// number of sub-tasks.
abstract class Job {
  /// Return the stream of sub-tasks for this job.
  ///
  /// These tasks will be executed in order, but in parallel with tasks from
  /// other jobs.
  Stream<WorkerJob> get tasks;

  /// Return the number of tasks in this job.
  ///
  /// May be calculated asynchronously, but must complete before the first
  /// task will be started.
  Future<int> get numTasks;
}

/// A class that represents a single task to be performed by a [ProcessPool].
///
/// Create a list of these to pass to [ProcessPool.startWorkers] or
/// [ProcessPool.runToCompletion].
class WorkerJob extends Job {
  WorkerJob(
    this.command, {
    String? name,
    this.workingDirectory,
    this.printOutput = false,
    this.stdin,
    this.stdinRaw,
    this.failOk = true,
    this.runInShell = false,
  }) : name = name ?? command.join(' ');

  /// The name of the job.
  ///
  /// Defaults to the args joined by a space.
  final String name;

  /// The name and arguments for the process, including the command name as
  /// command[0].
  final List<String> command;

  /// The working directory that the command should be executed in.
  final Directory? workingDirectory;

  /// If set, the stream to read the stdin for this process from.
  ///
  /// It will be encoded using the [ProcessPool.encoding] before being sent to
  /// the process.
  ///
  /// If both [stdin] and [stdinRaw] are set, only [stdinRaw] will be used.
  final Stream<String>? stdin;

  /// If set, the stream to read the raw stdin for this process from.
  ///
  /// It will be used directly, and not encoded (as [stdin] would be).
  ///
  /// If both [stdin] and [stdinRaw] are set, only [stdinRaw] will be used.
  final Stream<List<int>>? stdinRaw;

  /// Whether or not this command should print it's stdout when it runs.
  final bool printOutput;

  /// Whether or not failure of this job should throw an exception.
  ///
  /// If `failOk` is false, and this job fails (returns a non-zero exit code, or
  /// otherwise fails to start), then a [ProcessRunnerException] will be thrown
  /// containing the details.
  ///
  /// Defaults to true, since the [result] will contain the exit code.
  final bool failOk;

  /// If set to true, the process will run be spawned through a system shell.
  ///
  /// Running in a shell is generally not recommended, as it provides worse
  /// performance, and some security risk, but is sometimes necessary for
  /// accessing the shell environment. Shell command line expansion and
  /// interpolation is not performed on the commands, but you can execute shell
  /// builtins. Use the shell builtin "eval" (on Unix systems) if you want to
  /// execute shell commands with expansion.
  ///
  /// On Linux and OS X, `/bin/sh` is used, while on Windows,
  /// `%WINDIR%\system32\cmd.exe` is used.
  ///
  /// Defaults to false.
  final bool runInShell;

  /// Once the job is complete, this contains the result of the job.
  ///
  /// The [stderr], [stdout], and [output] accessors will decode their raw
  /// equivalents using the [ProcessRunner.decoder] that is set on the process
  /// runner for the pool that ran this job.
  ///
  /// If no process runner is supplied to the pool, then the decoder will be the
  /// same as the [ProcessPool.encoding] that was set on the pool.
  ///
  /// The initial value of this field is [ProcessRunnerResult.emptySuccess],
  /// and is updated when the job is complete.
  ProcessRunnerResult result = ProcessRunnerResult.emptySuccess;

  /// Once the job is complete, if it had an exception while running, this
  /// member contains the exception.
  Exception? exception;

  @override
  Stream<WorkerJob> get tasks async* {
    yield this;
  }

  @override
  Future<int> get numTasks async => 1;

  @override
  String toString() => command.join(' ');
}

class WorkerTaskGroup extends Job {
  WorkerTaskGroup(this.workers);

  final Iterable<WorkerJob> workers;

  @override
  Stream<WorkerJob> get tasks async* {
    yield* StreamGroup.merge(workers.map((WorkerJob worker) => worker.tasks));
  }

  @override
  Future<int> get numTasks async {
    int numTasks = 0;
    for (final WorkerJob job in workers) {
      numTasks += await job.numTasks;
    }
    return numTasks;
  }
}

/// The type of the reporting function for [ProcessPool.printReport].
typedef ProcessPoolProgressReporter = void Function(
  int totalJobs,
  int completed,
  int inProgress,
  int pending,
  int groupsPending,
  int failed,
);

/// A pool of worker processes that will keep [numWorkers] busy until all of the
/// (presumably single-threaded) processes are finished.
class ProcessPool {
  ProcessPool({
    int? numWorkers,
    ProcessRunner? processRunner,
    this.printReport = defaultPrintReport,
    this.encoding = const SystemEncoding(),
  })  : processRunner = processRunner ?? ProcessRunner(decoder: encoding),
        numWorkers = numWorkers ?? Platform.numberOfProcessors;

  /// A function to be called periodically to update the progress on the pool.
  ///
  /// May be set to null if no progress report is desired.
  ///
  /// Defaults to [defaultProgressReport], which prints the progress report to
  /// stdout.
  final ProcessPoolProgressReporter? printReport;

  /// The decoder to use for decoding the stdout, stderr, and output of a
  /// process, and encoding the stdin from the job.
  ///
  /// Defaults to an instance of [SystemEncoding].
  final Encoding encoding;

  /// The process runner to use when running the jobs in the pool.
  ///
  /// Setting this allows for configuration of the process runnner.
  ///
  /// Be default, a default-constructed [ProcessRunner] is used.
  final ProcessRunner processRunner;

  /// The number of workers to use for this pool.
  ///
  /// Defaults to the number of processors the machine has.
  final int numWorkers;

  /// Returns the number of jobs currently in progress.
  int get inProgressJobs => _inProgressTasks;
  int _inProgressTasks = 0;

  /// Returns the number of jobs that have been completed
  int get completedJobs => _completedTasks.length;

  /// Returns the number of jobs that are pending.
  int get pendingJobs => _pendingTasksCount;

  /// Returns the number of groups that are pending.
  int get pendingTaskGroups => _pendingTaskGroups.length;

  /// Returns the number of jobs that have failed so far.
  int get failedJobs => _failedTasks.length;

  /// Returns the total number of jobs that have been given to this pool.
  int get totalJobs {
    return _completedTasks.length + _inProgressTasks + _pendingTasksCount + _failedTasks.length;
  }
  int _pendingTasksCount = 0;

  final List<Job> _pendingTaskGroups = <Job>[];
  final List<WorkerJob> _failedTasks = <WorkerJob>[];
  final List<WorkerJob> _completedTasks = <WorkerJob>[];

  void _printReportIfNeeded() {
    if (printReport == null) {
      return;
    }
    printReport?.call(totalJobs, _completedTasks.length, _inProgressTasks, _pendingTasksCount, _pendingTaskGroups.length, _failedTasks.length);
  }

  static String defaultReportToString(
    int total,
    int completed,
    int inProgress,
    int pending,
    int groupsPending,
    int failed,
  ) {
    final String percent = total == 0 ? '100' : ((100 * (completed + failed)) ~/ total).toString().padLeft(3);
    final String completedStr = completed.toString().padLeft(3);
    final String totalStr = total.toString().padRight(3);
    final String inProgressStr = inProgress.toString().padLeft(2);
    final String pendingStr = pending.toString().padLeft(3);
    final String pendingGroupsStr = groupsPending.toString().padLeft(3);
    final String failedStr = failed.toString().padLeft(3);
    return 'Jobs: $percent% done, $completedStr/$totalStr completed, $inProgressStr in progress, $pendingStr pending (in $pendingGroupsStr groups), $failedStr failed.    \r';
  }

  /// The default report printing function, if one is not supplied.
  static void defaultPrintReport(
    int total,
    int completed,
    int inProgress,
    int pending,
    int groupsPending,
    int failed,
  ) {
    stdout.write(defaultReportToString(total, completed, inProgress, pending, groupsPending, failed));
  }

  Stream<WorkerJob> _performTasks(Job job) async* {
    await for (final WorkerJob job in job.tasks) {
      try {
        _inProgressTasks++;
        _printReportIfNeeded();
        job.result = await processRunner.runProcess(
          job.command,
          workingDirectory: job.workingDirectory ?? processRunner.defaultWorkingDirectory,
          printOutput: job.printOutput,
          stdin: job.stdinRaw ?? encoding.encoder.bind(job.stdin ?? const Stream<String>.empty()),
          // Starting process pool jobs in any other mode makes no sense: they
          // would all just be immediately started and bring the machine to its
          // knees.
          startMode: ProcessStartMode.normal,
          runInShell: job.runInShell,
          failOk: false, // Must be false so that we can catch the exception below.
        );
        _completedTasks.add(job);
      } on ProcessRunnerException catch (e) {
        job.result = e.result ?? ProcessRunnerResult.failed;
        job.exception = e;
        _failedTasks.add(job);
        if (!job.failOk) {
          rethrow;
        }
      } finally {
        _inProgressTasks--;
        _printReportIfNeeded();
        yield job;
      }
    }
  }

  Stream<WorkerJob> _startWorker() async* {
    while (_pendingTaskGroups.isNotEmpty) {
      final Job newJob = _pendingTaskGroups.removeAt(0);
      _pendingTasksCount = 0;
      final List<Job> jobs = _pendingTaskGroups.toList();
      for (final Job job in jobs) {
        _pendingTasksCount += await job.numTasks;
      }
      _printReportIfNeeded();
      yield* _performTasks(newJob);
    }
  }

  /// Runs all of the jobs to completion, and returns a list of completed jobs
  /// when all have been completed.
  ///
  /// To listen to jobs as they are completed, use [startWorkers] instead.
  Future<List<WorkerJob>> runToCompletion(List<Job> jobs) async {
    final List<WorkerJob> results = <WorkerJob>[];
    await startWorkers(jobs).forEach(results.add);
    return results;
  }

  /// Runs the `jobs` in parallel, with at most [numWorkers] jobs running
  /// simultaneously.
  ///
  /// If the supplied job is a [WorkerTaskGroup], then the jobs in the task
  /// group will be run so that the tasks are executed in order (but still in
  /// parallel with other jobs).
  ///
  /// Returns the the jobs in a [Stream] as they are completed.
  Stream<WorkerJob> startWorkers(Iterable<Job> jobs) async* {
    assert(_inProgressTasks == 0);
    _failedTasks.clear();
    _completedTasks.clear();
    _pendingTasksCount = 0;
    _pendingTaskGroups.clear();
    if (jobs.isEmpty) {
      return;
    }
    _pendingTaskGroups.addAll(jobs);
    for (final Job job in jobs) {
      _pendingTasksCount += await job.numTasks;
    }
    _printReportIfNeeded();
    final List<Stream<WorkerJob>> streams = <Stream<WorkerJob>>[];
    for (int i = 0; i < numWorkers; ++i) {
      if (_pendingTaskGroups.isEmpty) {
        break;
      }
      streams.add(_startWorker());
    }
    await for (final WorkerJob job in StreamGroup.merge<WorkerJob>(streams)) {
      yield job;
    }
    assert(_inProgressTasks == 0);
    assert(_pendingTaskGroups.isEmpty);
    return;
  }
}
