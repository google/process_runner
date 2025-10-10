// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:process/process.dart';
import 'package:test/test.dart' as test_package show TypeMatcher;
import 'package:test/test.dart' hide TypeMatcher, isInstanceOf;

test_package.TypeMatcher<T> isInstanceOf<T>() => isA<T>();

class FakeInvocationRecord {
  FakeInvocationRecord(
    this.invocation, {
    this.workingDirectory,
    this.runInShell = false,
    this.includeParentEnvironment = true,
  });
  final List<String> invocation;
  final String? workingDirectory;
  final bool runInShell;
  final bool includeParentEnvironment;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    if (other is! FakeInvocationRecord) {
      return false;
    }
    if (other.workingDirectory != workingDirectory) {
      return false;
    }
    if (other.runInShell != runInShell) {
      return false;
    }
    if (other.includeParentEnvironment != includeParentEnvironment) {
      return false;
    }
    if (other.invocation.length != invocation.length) {
      return false;
    }
    for (var i = 0; i < invocation.length; ++i) {
      if (other.invocation[i] != invocation[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(
      [workingDirectory, runInShell, includeParentEnvironment, ...invocation]);

  @override
  String toString() {
    return 'FakeInvocationRecord(invocation: $invocation, '
        'workingDirectory: $workingDirectory, runInShell: $runInShell, '
        'includeParentEnvironment: $includeParentEnvironment)';
  }
}

/// A mock that can be used to fake a process manager that runs commands and
/// returns results.
///
/// Call [verifyCalls] to verify that each desired call occurred.
class FakeProcessManager implements ProcessManager {
  FakeProcessManager(this.stdinResults, {this.commandsThrow = false});

  /// The callback that will be called each time stdin input is supplied to
  /// a call.
  final StringReceivedCallback stdinResults;

  /// Set to true if all commands run with this process manager should throw an
  /// exception.
  bool commandsThrow;

  /// The list of results that will be sent back, organized by the command line
  /// that will produce them. Each command line has a list of returned stdout
  /// output that will be returned on each successive call.
  Map<FakeInvocationRecord, List<ProcessResult>> _fakeResults =
      <FakeInvocationRecord, List<ProcessResult>>{};
  Map<FakeInvocationRecord, List<ProcessResult>> get fakeResults =>
      _fakeResults;
  set fakeResults(Map<FakeInvocationRecord, List<ProcessResult>> value) {
    _fakeResults = <FakeInvocationRecord, List<ProcessResult>>{};
    for (final key in value.keys) {
      _fakeResults[key] =
          (value[key] ?? <ProcessResult>[ProcessResult(0, 0, '', '')]).toList();
    }
  }

  /// The list of invocations that occurred, in the order they occurred.
  List<FakeInvocationRecord> invocations = <FakeInvocationRecord>[];

  /// Verify that the given command lines were called, in the given order, and
  /// that the parameters were in the same order.
  void verifyCalls(Iterable<FakeInvocationRecord> calls) {
    var index = 0;
    expect(invocations.length, equals(calls.length));
    for (final call in calls) {
      expect(call.invocation, orderedEquals(invocations[index].invocation));
      expect(
          call.workingDirectory, equals(invocations[index].workingDirectory));
      index++;
    }
  }

  ProcessResult _popResult(FakeInvocationRecord command) {
    expect(fakeResults, isNotEmpty);
    final foundResult = fakeResults[command];
    expect(foundResult, isNotNull,
        reason: '$command not found in expected results.');
    expect(foundResult, isNotEmpty);
    return fakeResults[command]!.removeAt(0);
  }

  FakeProcess _popProcess(FakeInvocationRecord command) =>
      FakeProcess(_popResult(command), stdinResults);

  Future<Process> _nextProcess(
    List<String> invocation, {
    String? workingDirectory,
    bool runInShell = false,
    bool includeParentEnvironment = true,
  }) async {
    final record = FakeInvocationRecord(
      invocation,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
    invocations.add(record);
    return Future<Process>.value(_popProcess(record));
  }

  ProcessResult _nextResultSync(
    List<String> invocation, {
    String? workingDirectory,
    bool runInShell = false,
    bool includeParentEnvironment = true,
  }) {
    final record = FakeInvocationRecord(
      invocation,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
    invocations.add(record);
    return _popResult(record);
  }

  Future<ProcessResult> _nextResult(
    List<String> invocation, {
    String? workingDirectory,
    bool runInShell = false,
    bool includeParentEnvironment = true,
  }) async {
    final record = FakeInvocationRecord(
      invocation,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
    invocations.add(record);
    return Future<ProcessResult>.value(_popResult(record));
  }

  @override
  bool canRun(dynamic executable, {String? workingDirectory}) {
    return true;
  }

  @override
  bool killPid(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    return true;
  }

  @override
  Future<ProcessResult> run(
    List<dynamic> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    if (commandsThrow) {
      throw const ProcessException('failed_executable', <String>[]);
    }
    return _nextResult(
      command as List<String>,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
  }

  @override
  ProcessResult runSync(
    List<dynamic> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    if (commandsThrow) {
      throw const ProcessException('failed_executable', <String>[]);
    }
    return _nextResultSync(
      command as List<String>,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
  }

  @override
  Future<Process> start(
    List<dynamic> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    if (commandsThrow) {
      throw const ProcessException('failed_executable', <String>[]);
    }
    return _nextProcess(
      command as List<String>,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
      includeParentEnvironment: includeParentEnvironment,
    );
  }
}

typedef StdinResults = void Function(String input);

/// A fake process that can be used to interact with a process "started" by the
/// FakeProcessManager.
class FakeProcess implements Process {
  FakeProcess(ProcessResult result, StdinResults stdinResults)
      : stdoutStream =
            Stream<List<int>>.value((result.stdout as String).codeUnits),
        stderrStream =
            Stream<List<int>>.value((result.stderr as String).codeUnits),
        desiredExitCode = result.exitCode,
        stdinSink = IOSink(StringStreamConsumer(stdinResults));

  final IOSink stdinSink;
  final Stream<List<int>> stdoutStream;
  final Stream<List<int>> stderrStream;
  final int desiredExitCode;

  @override
  Future<int> get exitCode => Future<int>.value(desiredExitCode);

  @override
  int get pid => 0;

  @override
  IOSink get stdin => stdinSink;

  @override
  Stream<List<int>> get stderr => stderrStream;

  @override
  Stream<List<int>> get stdout => stdoutStream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return true;
  }
}

/// Callback used to receive stdin input when it occurs.
typedef StringReceivedCallback = void Function(String received);

/// A stream consumer class that consumes UTF8 strings as lists of ints.
class StringStreamConsumer implements StreamConsumer<List<int>> {
  StringStreamConsumer(this.sendString);

  List<Stream<List<int>>> streams = <Stream<List<int>>>[];
  List<StreamSubscription<List<int>>> subscriptions =
      <StreamSubscription<List<int>>>[];
  List<Completer<dynamic>> completers = <Completer<dynamic>>[];

  /// The callback called when this consumer receives input.
  StringReceivedCallback sendString;

  @override
  Future<dynamic> addStream(Stream<List<int>> value) {
    streams.add(value);
    completers.add(Completer<dynamic>());
    subscriptions.add(
      value.listen((List<int> data) {
        sendString(utf8.decode(data));
      }),
    );
    subscriptions.last.onDone(() => completers.last.complete(null));
    return Future<dynamic>.value(null);
  }

  @override
  Future<dynamic> close() async {
    for (final completer in completers) {
      await completer.future;
    }
    completers.clear();
    streams.clear();
    subscriptions.clear();
    return Future<dynamic>.value(null);
  }
}
