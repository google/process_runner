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

/// A mock that can be used to fake a process manager that runs commands
/// and returns results.
///
/// Call [setResults] to provide a list of results that will return from
/// each command line (with arguments).
///
/// Call [verifyCalls] to verify that each desired call occurred.
class FakeProcessManager implements ProcessManager {
  FakeProcessManager(this.stdinResults, {this.commandsThrow = false});

  /// The callback that will be called each time stdin input is supplied to
  /// a call.
  final StringReceivedCallback stdinResults;

  /// Set to true if all commands run with this process manager should throw an
  /// exception.
  final bool commandsThrow;

  /// The list of results that will be sent back, organized by the command line
  /// that will produce them. Each command line has a list of returned stdout
  /// output that will be returned on each successive call.
  Map<List<String>, List<ProcessResult>> _fakeResults = <List<String>, List<ProcessResult>>{};
  Map<List<String>, List<ProcessResult>> get fakeResults => _fakeResults;
  set fakeResults(Map<List<String>, List<ProcessResult>> value) {
    _fakeResults = <List<String>, List<ProcessResult>>{};
    for (final List<String> key in value.keys) {
      _fakeResults[key] = (value[key] ?? <ProcessResult>[ProcessResult(0, 0, '', '')]).toList();
    }
  }

  /// The list of invocations that occurred, in the order they occurred.
  List<List<String>> invocations = <List<String>>[];

  /// Verify that the given command lines were called, in the given order, and
  /// that the parameters were in the same order.
  void verifyCalls(Iterable<List<String>> calls) {
    int index = 0;
    expect(invocations.length, equals(calls.length));
    for (final List<String> call in calls) {
      expect(call, orderedEquals(invocations[index]));
      index++;
    }
  }

  ProcessResult _popResult(List<String> command) {
    expect(fakeResults, isNotEmpty);
    List<ProcessResult> foundResult;
    List<String> foundCommand;
    for (final List<String> fakeCommand in fakeResults.keys) {
      if (fakeCommand.length != command.length) {
        continue;
      }
      bool listsIdentical = true;
      for (int i = 0; i < fakeCommand.length; ++i) {
        if (fakeCommand[i] != command[i]) {
          listsIdentical = false;
          break;
        }
      }
      if (listsIdentical) {
        foundResult = fakeResults[fakeCommand];
        foundCommand = fakeCommand;
        break;
      }
    }
    expect(foundResult, isNotNull, reason: '$command not found in expected results.');
    expect(foundResult, isNotEmpty);
    return fakeResults[foundCommand]?.removeAt(0) ?? ProcessResult(0, 0, '', '');
  }

  FakeProcess _popProcess(List<String> command) => FakeProcess(_popResult(command), stdinResults);

  Future<Process> _nextProcess(List<String> invocation) async {
    invocations.add(invocation);
    return Future<Process>.value(_popProcess(invocation));
  }

  ProcessResult _nextResultSync(List<String> invocation) {
    invocations.add(invocation);
    return _popResult(invocation);
  }

  Future<ProcessResult> _nextResult(List<String> invocation) async {
    invocations.add(invocation);
    return Future<ProcessResult>.value(_popResult(invocation));
  }

  @override
  bool canRun(dynamic executable, {String workingDirectory}) {
    return true;
  }

  @override
  bool killPid(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    return true;
  }

  @override
  Future<ProcessResult> run(
    List<dynamic> command, {
    String workingDirectory,
    Map<String, String> environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding stdoutEncoding = systemEncoding,
    Encoding stderrEncoding = systemEncoding,
  }) {
    if (commandsThrow) {
      throw const ProcessException('failed_executable', <String>[]);
    }
    return _nextResult(command as List<String>);
  }

  @override
  ProcessResult runSync(
    List<dynamic> command, {
    String workingDirectory,
    Map<String, String> environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding stdoutEncoding = systemEncoding,
    Encoding stderrEncoding = systemEncoding,
  }) {
    if (commandsThrow) {
      throw const ProcessException('failed_executable', <String>[]);
    }
    return _nextResultSync(command as List<String>);
  }

  @override
  Future<Process> start(
    List<dynamic> command, {
    String workingDirectory,
    Map<String, String> environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    if (commandsThrow) {
      throw const ProcessException('failed_executable', <String>[]);
    }
    return _nextProcess(command as List<String>);
  }
}

typedef StdinResults = void Function(String input);

/// A fake process that can be used to interact with a process "started" by the
/// FakeProcessManager.
class FakeProcess implements Process {
  FakeProcess(ProcessResult result, StdinResults stdinResults)
      : stdoutStream = Stream<List<int>>.value((result.stdout as String).codeUnits),
        stderrStream = Stream<List<int>>.value((result.stderr as String).codeUnits),
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
  List<StreamSubscription<List<int>>> subscriptions = <StreamSubscription<List<int>>>[];
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
    for (final Completer<dynamic> completer in completers) {
      await completer.future;
    }
    completers.clear();
    streams.clear();
    subscriptions.clear();
    return Future<dynamic>.value(null);
  }
}
