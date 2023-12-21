// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show Encoding;
import 'dart:io' show Directory, Platform, stdout, SystemEncoding, stderr, ProcessStartMode;

import 'package:async/async.dart' show StreamGroup;

import 'process_runner.dart';

abstract class DependentJob {
  /// The name of the job.
  String get name;

  /// Other jobs that this job depends on.
  ///
  /// This job will not be scheduled until all of the jobs in this set have
  /// completed.
  ///
  /// Will throw if there is a dependency cycle, or if the given job has not
  /// been added to the pool.
  ///
  /// Defaults to an empty set.
  Set<DependentJob> get dependsOn;

  void addToQueue(List<DependentJob> jobs);
}

/// A class that represents a job to be done by a [ProcessPool].
///
/// Create a list of these to pass to [ProcessPool.startWorkers] or
/// [ProcessPool.runToCompletion].
class WorkerJob extends DependentJob {
  WorkerJob(
    this.command, {
    String? name,
    this.workingDirectory,
    this.printOutput = false,
    this.stdin,
    this.stdinRaw,
    this.failOk = true,
    this.runInShell = false,
    Iterable<DependentJob>? dependsOn,
  })  : name = name ?? command.join(' '),
        dependsOn = dependsOn?.toSet() ?? <DependentJob>{};

  /// The name of the job.
  ///
  /// Defaults to the command args joined by spaces.
  @override
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
  void addToQueue(List<DependentJob> jobs) {
    jobs.add(this);
  }

  @override
  Set<DependentJob> dependsOn;

  @override
  String toString() => '${command.join(' ')} with ${dependsOn.length} dependencies';
}

class WorkerJobGroup extends DependentJob {
  WorkerJobGroup(
    this.workers, {
    this.name = '<unknown>',
    bool setDependencies = true,
  })  : dependsOn = workers.toSet(),
        assert(workers.isNotEmpty) {
    // Make sure they run in series.
    if (setDependencies) {
      for (int i = 1; i < workers.length; i++) {
        workers[i].dependsOn.add(workers[i - 1]);
      }
    }
  }

  @override
  final String name;

  /// The workers that will run in order because They depend on each other.
  final List<DependentJob> workers;

  @override
  final Set<DependentJob> dependsOn;

  @override
  void addToQueue(List<DependentJob> jobs) {
    jobs.addAll(workers);
    jobs.add(this);
  }

  @override
  String toString() => '${name.isNotEmpty ? name : 'Group'} with ${workers.length} members';
}

/// The type of the reporting function for [ProcessPool.printReport].
typedef ProcessPoolProgressReporter = void Function(
  int totalJobs,
  int completed,
  int inProgress,
  int pending,
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
  int get inProgressJobs => _inProgressJobs;
  int _inProgressJobs = 0;

  /// Returns the number of jobs that have been completed
  int get completedJobs => _completedJobs.length;

  /// Returns the number of jobs that are pending.
  int get pendingJobs => _pendingJobs.length;

  /// Returns the number of jobs that have failed so far.
  int get failedJobs => _failedJobs.length;

  /// Returns the total number of jobs that have been given to this pool.
  int get totalJobs => _completedJobs.length + _inProgressJobs + _pendingJobs.length + _failedJobs.length;

  final List<DependentJob> _pendingJobs = <DependentJob>[];
  final List<DependentJob> _failedJobs = <DependentJob>[];
  final List<DependentJob> _completedJobs = <DependentJob>[];

  void _printReportIfNeeded() {
    if (printReport == null) {
      return;
    }
    printReport?.call(totalJobs, _completedJobs.length, _inProgressJobs, _pendingJobs.length, _failedJobs.length);
  }

  static String defaultReportToString(
    int total,
    int completed,
    int inProgress,
    int pending,
    int failed,
  ) {
    final String percent = total == 0 ? '100' : ((100 * (completed + failed)) ~/ total).toString().padLeft(3);
    final String completedStr = completed.toString().padLeft(3);
    final String totalStr = total.toString().padRight(3);
    final String inProgressStr = inProgress.toString().padLeft(2);
    final String pendingStr = pending.toString().padLeft(3);
    final String failedStr = failed.toString().padLeft(3);
    return 'Jobs: $percent% done, $completedStr/$totalStr completed, $inProgressStr in progress, $pendingStr pending, $failedStr failed.    \r';
  }

  /// The default report printing function, if one is not supplied.
  static void defaultPrintReport(
    int total,
    int completed,
    int inProgress,
    int pending,
    int failed,
  ) {
    stdout.write(defaultReportToString(total, completed, inProgress, pending, failed));
  }

  Future<WorkerJob> _performJob(WorkerJob job) async {
    try {
      if (job.dependsOn.intersection(_failedJobs.toSet()).isNotEmpty) {
        // A dependent job has failed, so just immediately fail this one instead
        // of starting it.
        _addFailedJob(
          job,
          ProcessRunnerException(
            'One or more dependent jobs failed.',
            result: ProcessRunnerResult.failed,
          ),
        );
        return job;
      }
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
      _completedJobs.add(job);
    } on ProcessRunnerException catch (e) {
      _addFailedJob(job, e);
      if (!job.failOk) {
        rethrow;
      }
    } finally {
      _inProgressJobs--;
      _printReportIfNeeded();
    }
    return job;
  }

  void _addFailedJob(WorkerJob job, ProcessRunnerException e) {
    job.result = e.result ?? ProcessRunnerResult.failed;
    job.exception = e;
    _failedJobs.add(job);
  }

  DependentJob? _getNextInependentJob() {
    if (_pendingJobs.isEmpty) {
      return null;
    }
    if (inProgressJobs == 0 && _completedJobs.isEmpty && _failedJobs.isEmpty) {
      final int firstIndependent = _pendingJobs.indexWhere((DependentJob element) => element.dependsOn.isEmpty);
      if (firstIndependent == -1) {
        throw ProcessRunnerException(
          'Nothing is in progress, and no pending jobs are without dependencies. '
          'At least one must have no dependencies so that something can start.',
        );
      }
      return _pendingJobs.removeAt(firstIndependent);
    }
    // Go through the list of jobs, looking for the first one where all of its
    // dependencies have been satisfied by appearing in the _completedJobs list.
    final Set<DependentJob> allFinishedJobs = _completedJobs.toSet().union(_failedJobs.toSet());
    for (int i = 0; i < _pendingJobs.length; i += 1) {
      final DependentJob job = _pendingJobs[i];
      if (job.dependsOn.isEmpty || job.dependsOn.difference(allFinishedJobs.toSet()).isEmpty) {
        return _pendingJobs.removeAt(i);
      }
    }
    // This can be the case if all the dependent jobs are still running.
    return null;
  }

  Stream<WorkerJob> _startWorker() async* {
    while (_pendingJobs.isNotEmpty) {
      final DependentJob? newJob = _getNextInependentJob();
      if (newJob == null && _inProgressJobs > 0) {
        // All the dependent jobs are still pending.
        // Small pause to let pending jobs complete, so we don't just spin.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        continue;
      }
      if (newJob is! WorkerJob) {
        // Just finish up any groups immediately now that all of their workers
        // are done. We keep them until now just in case a job depends on a
        // group. Don't yield these jobs either, since we don't want groups in
        // the output, just completed WorkerJobs.
        if (newJob is WorkerJobGroup) {
          _completedJobs.add(newJob);
        }
        continue;
      }
      _inProgressJobs++;
      yield await _performJob(newJob);
    }
  }

  /// Runs all of the jobs to completion, and returns a list of completed jobs
  /// when all have been completed.
  ///
  /// To listen to jobs as they are completed, use [startWorkers] instead.
  Future<List<WorkerJob>> runToCompletion(Iterable<DependentJob> jobs) async {
    final List<WorkerJob> results = <WorkerJob>[];
    await startWorkers(jobs).forEach(results.add);
    return results;
  }

  /// Runs the `jobs` in parallel, with at most [numWorkers] jobs running
  /// simultaneously.
  ///
  /// If the supplied job is a [WorkerJobGroup], then the jobs in the task
  /// group will be run so that the tasks are executed in order (but still in
  /// parallel with other jobs).
  ///
  /// Returns the the jobs in a [Stream] as they are completed.
  Stream<WorkerJob> startWorkers(Iterable<DependentJob> jobs) async* {
    assert(_inProgressJobs == 0);
    _failedJobs.clear();
    _completedJobs.clear();
    if (jobs.isEmpty) {
      return;
    }
    for (final DependentJob job in jobs) {
      job.addToQueue(_pendingJobs);
    }
    _verifyDependencies();
    final List<Stream<WorkerJob>> streams = <Stream<WorkerJob>>[];
    for (int i = 0; i < numWorkers; ++i) {
      if (_pendingJobs.isEmpty) {
        break;
      }
      streams.add(_startWorker());
    }
    await for (final WorkerJob job in StreamGroup.merge<WorkerJob>(streams)) {
      yield job;
    }
    assert(_pendingJobs.isEmpty);
    assert(_inProgressJobs == 0);
    _printReportIfNeeded();
    return;
  }

  bool _hasDependencyLoop(DependentJob job, {required Set<DependentJob> visited}) {
    // Check if the job has already been visited, indicating a potential loop
    if (visited.contains(job)) {
      return true;
    }

    // Add the current job to visited set for tracking
    visited.add(job);

    // Loop through each dependency of the current job
    for (final DependentJob dependentJob in job.dependsOn) {
      // Recursively check for loops in dependent jobs
      if (_hasDependencyLoop(dependentJob, visited: visited)) {
        return true;
      }
    }

    // Remove the current job from visited set after processing its dependencies
    visited.remove(job);

    // No loop found after checking all dependencies
    return false;
  }

  void _verifyDependencies() {
    // Dependencies for all jobs must also appear in the pending jobs.
    assert(_completedJobs.isEmpty && _inProgressJobs == 0, "Can't verify dependencies once started.");
    final Set<DependentJob> pending = _pendingJobs.toSet();
    for (final DependentJob job in pending) {
      final Set<DependentJob> diff = job.dependsOn.difference(pending);
      if (diff.isNotEmpty) {
        throw ProcessRunnerException("${job.name} has dependent jobs that aren't scheduled to be run:\n"
            "  ${diff.map<String>((DependentJob item) => item.name).join('\n  ')}");
      }
    }
    // Check for dependency loops.
    for (final DependentJob job in pending) {
      final Set<DependentJob> visited = <DependentJob>{};
      if (_hasDependencyLoop(job, visited: visited)) {
        throw ProcessRunnerException('Dependency loop detected in:\n'
            '  ${job.name}: $job\n'
            'Which depends on:\n'
            "  ${job.dependsOn.map((DependentJob item) => item.name).join('\n  ')}"
            'Dependency loop:\n'
            "  ${visited.map((DependentJob item) => item.name).join('\n  ')}");
      }
    }
  }
}
