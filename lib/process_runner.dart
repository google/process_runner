// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

import 'dart:async' show Completer;
import 'dart:convert' show utf8;
import 'dart:io'
    show
        Process,
        ProcessResult,
        ProcessException,
        Directory,
        Platform,
        stderr,
        stdout;

Platform defaultPlatform = Platform();

/// Exception class for when a process fails to run, so we can catch
/// it and provide something more readable than a stack trace.
class ProcessRunnerException implements Exception {
  ProcessRunnerException(this.message, {this.result});

  final String message;
  final ProcessResult? result;

  int get exitCode => result?.exitCode ?? -1;

  @override
  String toString() {
    String output = runtimeType.toString();
    output += ': $message';
    final String stderr = (result?.stderr ?? '') as String;
    if (stderr.isNotEmpty) {
      output += ':\n$stderr';
    }
    return output;
  }
}

class ProcessRunnerResult {
  const ProcessRunnerResult(
      this.exitCode, this.stdout, this.stderr, this.output);
  final int exitCode;
  final List<int> stdout;
  final List<int> stderr;
  final List<int> output;
}

/// A helper class for classes that want to run a process, optionally have the
/// stderr and stdout reported as the process runs, and capture the stdout
/// properly without dropping any.
class ProcessRunner {
  ProcessRunner({
    this.defaultWorkingDirectory,
  });

  /// Sets the default directory used when `workingDirectory` is not specified
  /// to [runProcess].
  final Directory? defaultWorkingDirectory;

  /// The environment to run processes with.
  Map<String, String> environment =
      Map<String, String>.from(Platform.environment);

  /// Run the command and arguments in `commandLine` as a sub-process from
  /// `workingDirectory` if set, or the [defaultWorkingDirectory] if not. Uses
  /// [Directory.current] if [defaultWorkingDirectory] is not set.
  ///
  /// Set `failOk` if [runProcess] should not throw an exception when the
  /// command completes with a a non-zero exit code.
  Future<ProcessRunnerResult> runProcess(
    List<String> commandLine, {
    Directory? workingDirectory,
    bool printOutput = true,
    bool failOk = false,
    Stream<List<int>>? stdin,
  }) async {
    workingDirectory ??= defaultWorkingDirectory ?? Directory.current;
    if (printOutput) {
      stderr.write(
          'Running "${commandLine.join(' ')}" in ${workingDirectory.path}.\n');
    }
    final List<int> stdoutOutput = <int>[];
    final List<int> stderrOutput = <int>[];
    final List<int> combinedOutput = <int>[];
    final Completer<void> stdoutComplete = Completer<void>();
    final Completer<void> stderrComplete = Completer<void>();
    final Completer<void> stdinComplete = Completer<void>();

    Process? process;
    Future<int> allComplete() async {
      if (stdin != null) {
        await stdinComplete.future;
        await process?.stdin.close();
      }
      await stderrComplete.future;
      await stdoutComplete.future;
      return process?.exitCode ?? Future<int>.value(0);
    }

    try {
      process = await Process.start(
        commandLine.first,
        commandLine.sublist(1),
        workingDirectory: workingDirectory.absolute.path,
        environment: environment,
        runInShell: false,
      );
      if (stdin != null) {
        stdin.listen((List<int> data) {
          process?.stdin.add(data);
        }, onDone: () async => stdinComplete.complete());
      }
      process.stdout.listen(
        (List<int> event) {
          stdoutOutput.addAll(event);
          combinedOutput.addAll(event);
          if (printOutput) {
            stdout.add(event);
          }
        },
        onDone: () async => stdoutComplete.complete(),
      );
      process.stderr.listen(
        (List<int> event) {
          stderrOutput.addAll(event);
          combinedOutput.addAll(event);
          if (printOutput) {
            stderr.add(event);
          }
        },
        onDone: () async => stderrComplete.complete(),
      );
    } on ProcessException catch (e) {
      final String message =
          'Running "${commandLine.join(' ')}" in ${workingDirectory.path} '
          'failed with:\n${e.toString()}';
      throw ProcessRunnerException(message);
    } on ArgumentError catch (e) {
      final String message =
          'Running "${commandLine.join(' ')}" in ${workingDirectory.path} '
          'failed with:\n${e.toString()}';
      throw ProcessRunnerException(message);
    }

    final int exitCode = await allComplete();
    if (exitCode != 0 && !failOk) {
      final String message =
          'Running "${commandLine.join(' ')}" in ${workingDirectory.path} failed';
      throw ProcessRunnerException(
        message,
        result: ProcessResult(0, exitCode, null, 'exited with code $exitCode\n${utf8.decode(combinedOutput)}'),
      );
    }
    return ProcessRunnerResult(
        exitCode, stdoutOutput, stderrOutput, combinedOutput);
  }
}

class WorkerJob {
  WorkerJob(
    this.name,
    this.args, {
    this.workingDirectory,
    this.printOutput = false,
  });

  /// The name of the job.
  final String name;

  /// The arguments for the process, including the command name as args[0].
  final List<String> args;

  /// The working directory that the command should be executed in.
  final Directory? workingDirectory;

  /// Whether or not this command should print it's stdout when it runs.
  final bool printOutput;

  @override
  String toString() {
    return args.join(' ');
  }
}

/// A pool of worker processes that will keep [numWorkers] busy until all of the
/// (presumably single-threaded) processes are finished.
class ProcessPool {
  ProcessPool({int? numWorkers})
      : numWorkers = numWorkers ?? Platform.numberOfProcessors;

  ProcessRunner processRunner = ProcessRunner();
  int numWorkers;
  List<WorkerJob> pendingJobs = <WorkerJob>[];
  List<WorkerJob> failedJobs = <WorkerJob>[];
  Map<WorkerJob, Future<List<int>>> inProgressJobs =
      <WorkerJob, Future<List<int>>>{};
  Map<WorkerJob, ProcessRunnerResult> completedJobs =
      <WorkerJob, ProcessRunnerResult>{};
  Completer<Map<WorkerJob, ProcessRunnerResult>> completer =
      Completer<Map<WorkerJob, ProcessRunnerResult>>();

  void _printReport() {
    final int totalJobs =
        completedJobs.length + inProgressJobs.length + pendingJobs.length;
    final String percent = totalJobs == 0
        ? '100'
        : ((100 * completedJobs.length) ~/ totalJobs).toString().padLeft(3);
    final String completed = completedJobs.length.toString().padLeft(3);
    final String total = totalJobs.toString().padRight(3);
    final String inProgress = inProgressJobs.length.toString().padLeft(2);
    final String pending = pendingJobs.length.toString().padLeft(3);
    stdout.write(
        'Jobs: $percent% done, $completed/$total completed, $inProgress in progress, $pending pending.  \r');
  }

  Future<List<int>> _scheduleJob(WorkerJob job) async {
    final Completer<List<int>> jobDone = Completer<List<int>>();
    final List<int> output = <int>[];
    try {
      completedJobs[job] = await processRunner.runProcess(
        job.args,
        workingDirectory: job.workingDirectory,
        printOutput: job.printOutput,
      );
    } catch (e) {
      failedJobs.add(job);
      if (e is ProcessRunnerException) {
        print(e.toString());
        print('${utf8.decode(output)}');
      } else {
        print('\nJob $job failed: $e');
      }
    } finally {
      inProgressJobs.remove(job);
      if (pendingJobs.isNotEmpty) {
        final WorkerJob newJob = pendingJobs.removeAt(0);
        inProgressJobs[newJob] = _scheduleJob(newJob);
      } else {
        if (inProgressJobs.isEmpty) {
          completer.complete(completedJobs);
        }
      }
      jobDone.complete(output);
      _printReport();
    }
    return jobDone.future;
  }

  Future<Map<WorkerJob, ProcessRunnerResult>> startWorkers(
      List<WorkerJob> jobs) async {
    assert(inProgressJobs.isEmpty);
    assert(failedJobs.isEmpty);
    assert(completedJobs.isEmpty);
    if (jobs.isEmpty) {
      return <WorkerJob, ProcessRunnerResult>{};
    }
    pendingJobs = jobs;
    for (int i = 0; i < numWorkers; ++i) {
      if (pendingJobs.isEmpty) {
        break;
      }
      final WorkerJob job = pendingJobs.removeAt(0);
      inProgressJobs[job] = _scheduleJob(job);
    }
    return completer.future.then((Map<WorkerJob, ProcessRunnerResult> result) {
      stdout.flush();
      return result;
    });
  }
}
