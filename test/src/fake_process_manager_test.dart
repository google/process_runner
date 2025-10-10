// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:process_runner/test/fake_process_manager.dart';
import 'package:test/test.dart' hide TypeMatcher, isInstanceOf;

void main() {
  group('ArchivePublisher', () {
    final stdinCaptured = <String>[];
    void captureStdin(String item) {
      stdinCaptured.add(item);
    }

    var processManager = FakeProcessManager(captureStdin);

    setUp(() async {
      processManager = FakeProcessManager(captureStdin);
    });

    tearDown(() async {});

    test('start works', () async {
      final calls = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2']):
            <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
        FakeInvocationRecord(<String>['command2', 'arg1', 'arg2']):
            <ProcessResult>[
          ProcessResult(0, 0, 'output2', ''),
        ],
      };
      processManager.fakeResults = calls;
      for (final key in calls.keys) {
        final process = await processManager.start(key.invocation);
        var output = '';
        process.stdout.listen((List<int> item) {
          output += utf8.decode(item);
        });
        await process.exitCode;
        expect(output, equals((calls[key] ?? <ProcessResult>[])[0].stdout));
      }
      processManager.verifyCalls(calls.keys.toList());
    });

    test('run works', () async {
      final calls = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2']):
            <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
        FakeInvocationRecord(<String>['command2', 'arg1', 'arg2']):
            <ProcessResult>[
          ProcessResult(0, 0, 'output2', ''),
        ],
      };
      processManager.fakeResults = calls;
      for (final key in calls.keys) {
        final result = await processManager.run(key.invocation);
        expect(
            result.stdout, equals((calls[key] ?? <ProcessResult>[])[0].stdout));
      }
      processManager.verifyCalls(calls.keys.toList());
    });

    test('runSync works', () async {
      final calls = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2']):
            <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
        FakeInvocationRecord(<String>['command2', 'arg1', 'arg2']):
            <ProcessResult>[
          ProcessResult(0, 0, 'output2', ''),
        ],
      };
      processManager.fakeResults = calls;
      for (final key in calls.keys) {
        final result = processManager.runSync(key.invocation);
        expect(
            result.stdout, equals((calls[key] ?? <ProcessResult>[])[0].stdout));
      }
      processManager.verifyCalls(calls.keys.toList());
    });

    test('captures stdin', () async {
      final calls = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2']):
            <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
        FakeInvocationRecord(<String>['command2', 'arg1', 'arg2']):
            <ProcessResult>[
          ProcessResult(0, 0, 'output2', ''),
        ],
      };
      processManager.fakeResults = calls;
      for (final key in calls.keys) {
        final process = await processManager.start(key.invocation);
        var output = '';
        process.stdout.listen((List<int> item) {
          output += utf8.decode(item);
        });
        final testInput =
            '${(calls[key] ?? <ProcessResult>[])[0].stdout} input';
        process.stdin.add(testInput.codeUnits);
        await process.exitCode;
        expect(output, equals((calls[key] ?? <ProcessResult>[])[0].stdout));
        expect(stdinCaptured.last, equals(testInput));
      }
      processManager.verifyCalls(calls.keys.toList());
    });
  });
}
