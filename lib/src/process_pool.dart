// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show Encoding;
import 'dart:io'
    show Directory, Platform, ProcessStartMode, SystemEncoding, stderr, stdout;

import 'package:async/async.dart' show StreamGroup;
import '../process_runner.dart';

import 'process_runner.dart';

/// A type of job that can depend on other jobs.
///
/// This is the base type of [WorkerJob] and [WorkerJobGroup], which can all
/// depend on each other.
///
/// Jobs are not allowed to have a dependency cycle, meaning that they can't
/// depend on themselves, directly or indirectly. Will throw a
/// [ProcessRunnerException] if a cycle is detected.
abstract class DependentJob {
  DependentJob({Iterable<DependentJob> dependsOn = const <DependentJob>{}})
      : _dependsOn = dependsOn.toSet();

  /// The name of the job.
  String get name;

  /// Other jobs that this job depends on.
  ///
  /// This job will not be scheduled until all of the jobs in this set have
  /// completed.
  ///
  /// To add a dependency, call [addDependency] or [addDependencies].
  ///
  /// To remove a dependency, call [removeDependency] or [removeDependencies].
  ///
  /// Modifying the returned set will not affect the dependencies of this job.
  ///
  /// Will throw if there is a dependency cycle, or if the given job has not
  /// been added to the pool.
  ///
  /// Defaults to an empty set.
  Set<DependentJob> get dependsOn => _dependsOn.toSet();
  final Set<DependentJob> _dependsOn;

  /// Add a dependency to this job.
  ///
  /// The given job must complete before this job will executed.
  ///
  /// See also:
  ///
  /// * [removeDependency] which removes a single job.
  /// * [addDependencies] which adds all of the given jobs as dependencies
  ///   of this job.
  void addDependency(DependentJob job) {
    if (job == this) {
      throw ProcessRunnerException('A job cannot depend on itself');
    }
    if (_dependsOn.contains(job)) {
      return;
    }
    if (job._dependsOn.contains(this)) {
      throw ProcessRunnerException(
          '$this is already a dependency of $job, no cycle allowed');
    }
    _dependsOn.add(job);
  }

  /// Remove a dependency to this job that was added with [addDependency].
  ///
  /// If the given job is not a dependency of this job, this will assert.
  ///
  /// See also:
  ///
  /// * [addDependency] which adds a single job.
  /// * [removeDependencies] which removes all of the given jobs as dependencies
  ///   of this job.
  void removeDependency(DependentJob job) {
    assert(_dependsOn.contains(job));
    assert(job != this);
    _dependsOn.remove(job);
  }

  /// Adds all of the [jobs] as dependencies of this job.
  ///
  /// See also:
  ///
  /// * [addDependency] which adds a single job.
  /// * [removeDependencies] which removes all of the given jobs as dependencies
  ///   of this job.
  void addDependencies(Iterable<DependentJob> jobs) {
    // don't just add it to _dependsOn so that subclass addDependency will be
    // called.
    jobs.forEach(addDependency);
  }

  /// Removes all of the given [jobs] as dependencies of this job.
  ///
  /// See also:
  ///
  /// * [removeDependency] which removes a single job.
  /// * [addDependencies] which adds all of the given jobs as dependencies
  ///   of this job.
  void removeDependencies(Iterable<DependentJob> jobs) {
    // don't just remove it from _dependsOn so that subclass removeDependency
    // will be called.
    jobs.forEach(removeDependency);
  }

  /// Adds this job, and any jobs it manages to the given [jobQueue].
  ///
  /// This is called by [ProcessPool.startWorkers] and
  /// [ProcessPool.runToCompletion] to expand the jobs for this worker into
  /// individual jobs.
  void addToQueue(List<DependentJob> jobQueue);
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
        super(dependsOn: dependsOn?.toSet() ?? <DependentJob>{});

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
  /// The [stderr] and [stdout] accessors will decode their raw
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
  void addToQueue(List<DependentJob> jobQueue) {
    jobQueue.add(this);
  }

  @override
  String toString() => name;
}

/// A job that groups other jobs.
///
/// The [jobs] will be run in the order given to the constructor.
///
/// This group job finishes when all the workers finish.
class WorkerJobGroup extends DependentJob {
  WorkerJobGroup(Iterable<DependentJob> jobs,
      {Iterable<DependentJob>? dependsOn, this.name = 'Group'})
      : assert(jobs.isNotEmpty),
        jobs = jobs.toList(),
        super(dependsOn: <DependentJob>{
          ...jobs.toSet(),
          if (dependsOn != null) ...dependsOn
        }) {
    // Make sure they run in series, and they depend on anything that the group
    // depends on.
    if (dependsOn != null) {
      this.jobs.first.addDependencies(dependsOn);
    }
    for (var i = 1; i < this.jobs.length; i++) {
      this.jobs[i].addDependency(this.jobs[i - 1]);
    }
  }

  @override
  final String name;

  /// The jobs that will run in order because they depend on each other.
  final List<DependentJob> jobs;

  @override
  void addDependency(DependentJob job) {
    for (final worker in jobs) {
      worker.addDependency(job);
    }
    super.addDependency(job);
  }

  @override
  void removeDependency(DependentJob job) {
    for (final worker in jobs) {
      worker.removeDependency(job);
    }
    super.removeDependency(job);
  }

  @override
  void addToQueue(List<DependentJob> jobQueue) {
    jobQueue.addAll(jobs);
    jobQueue.add(this);
  }

  @override
  String toString() =>
      '${name.isNotEmpty ? name : 'Group'} with ${jobs.length} members';
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
  /// Defaults to [defaultPrintReport], which prints the progress report to
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
  int get totalJobs =>
      _completedJobs.length +
      _inProgressJobs +
      _pendingJobs.length +
      _failedJobs.length;

  final List<DependentJob> _pendingJobs = <DependentJob>[];
  final List<DependentJob> _failedJobs = <DependentJob>[];
  final List<DependentJob> _completedJobs = <DependentJob>[];

  void _printReportIfNeeded() {
    if (printReport == null) {
      return;
    }
    printReport?.call(
      totalJobs,
      _completedJobs.length,
      _inProgressJobs,
      _pendingJobs.length,
      _failedJobs.length,
    );
  }

  static String defaultReportToString(
    int total,
    int completed,
    int inProgress,
    int pending,
    int failed,
  ) {
    final percent = total == 0
        ? '100'
        : ((100 * (completed + failed)) ~/ total).toString().padLeft(3);
    final completedStr = completed.toString().padLeft(3);
    final totalStr = total.toString().padRight(3);
    final inProgressStr = inProgress.toString().padLeft(2);
    final pendingStr = pending.toString().padLeft(3);
    final failedStr = failed.toString().padLeft(3);
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
    stdout.write(
        defaultReportToString(total, completed, inProgress, pending, failed));
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
        workingDirectory:
            job.workingDirectory ?? processRunner.defaultWorkingDirectory,
        printOutput: job.printOutput,
        stdin: job.stdinRaw ??
            encoding.encoder.bind(job.stdin ?? const Stream<String>.empty()),
        // Starting process pool jobs in any other mode makes no sense: they
        // would all just be immediately started and bring the machine to its
        // knees.
        startMode: ProcessStartMode.normal,
        runInShell: job.runInShell,
        failOk:
            false, // Must be false so that we can catch the exception below.
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

  DependentJob? _getNextIndependentJob() {
    if (_pendingJobs.isEmpty) {
      return null;
    }
    if (inProgressJobs == 0 && _completedJobs.isEmpty && _failedJobs.isEmpty) {
      final firstIndependent = _pendingJobs
          .indexWhere((DependentJob element) => element.dependsOn.isEmpty);
      if (firstIndependent == -1) {
        throw ProcessRunnerException(
          'Nothing is in progress, and no pending jobs are without '
          'dependencies. At least one must have no dependencies so that '
          'something can start.',
        );
      }
      return _pendingJobs.removeAt(firstIndependent);
    }
    // Go through the list of jobs, looking for the first one where all of its
    // dependencies have been satisfied by appearing in the _completedJobs list.
    final allFinishedJobs = _completedJobs.toSet().union(_failedJobs.toSet());
    for (var i = 0; i < _pendingJobs.length; i += 1) {
      final job = _pendingJobs[i];
      if (job.dependsOn.isEmpty ||
          job.dependsOn.difference(allFinishedJobs.toSet()).isEmpty) {
        return _pendingJobs.removeAt(i);
      }
    }
    // This can be the case if all the dependent jobs are still running.
    return null;
  }

  Stream<WorkerJob> _startWorker() async* {
    while (_pendingJobs.isNotEmpty) {
      final newJob = _getNextIndependentJob();
      if (newJob == null && _inProgressJobs > 0) {
        // All the dependent jobs are still pending.
        // Small pause to let pending jobs complete, so we don't just spin.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        continue;
      }
      if (newJob is WorkerJobGroup) {
        // Just finish up any groups immediately now that all of their workers
        // are done. We keep them until now just in case a job depends on a
        // group. Don't yield these jobs either, since we don't want groups in
        // the output, just completed WorkerJobs.
        _completedJobs.add(newJob);
      } else if (newJob is WorkerJob) {
        _inProgressJobs++;
        yield await _performJob(newJob);
      }
    }
  }

  /// Runs all of the jobs to completion, and returns a list of completed jobs
  /// when all have been completed.
  ///
  /// To listen to jobs as they are completed, use [startWorkers] instead.
  Future<List<WorkerJob>> runToCompletion(Iterable<DependentJob> jobs) async {
    final results = <WorkerJob>[];
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
    for (final job in jobs) {
      job.addToQueue(_pendingJobs);
    }
    _verifyDependencies();
    final streams = <Stream<WorkerJob>>[];
    for (var i = 0; i < numWorkers; ++i) {
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

  bool _hasDependencyLoop(DependentJob job,
      {required Set<DependentJob> visited}) {
    if (visited.contains(job)) {
      return true;
    }
    visited.add(job);
    for (final dependentJob in job.dependsOn) {
      if (_hasDependencyLoop(dependentJob, visited: visited)) {
        return true;
      }
    }
    visited.remove(job);
    return false;
  }

  void _verifyDependencies() {
    // Dependencies for all jobs must also appear in the pending jobs.
    assert(_completedJobs.isEmpty && _inProgressJobs == 0,
        "Can't verify dependencies once started.");
    final pending = _pendingJobs.toSet();
    for (final job in pending) {
      final diff = job.dependsOn.difference(pending);
      if (diff.isNotEmpty) {
        final diffs =
            diff.map<String>((DependentJob item) => item.name).join('\n  ');
        throw ProcessRunnerException(
            "${job.name} has dependent jobs that aren't scheduled to be run:\n"
            '  $diffs');
      }
    }
    // Check for dependency loops.
    for (final job in pending) {
      final visited = <DependentJob>{};
      if (_hasDependencyLoop(job, visited: visited)) {
        throw ProcessRunnerException('Illegal dependency loop detected:\n'
            '  ${<DependentJob>[
          ...visited,
          job
        ].map((DependentJob item) => item.name).join('\n  ')}');
      }
    }
  }
}
