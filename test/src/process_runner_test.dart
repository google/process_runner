// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:process_runner/process_runner.dart';
import 'package:process_runner/test/fake_process_manager.dart';
import 'package:test/test.dart';

void main() {
  var fakeProcessManager = FakeProcessManager((String value) {});
  var processRunner = ProcessRunner(processManager: fakeProcessManager);
  final testPath = Platform.isWindows ? r'C:\tmp\foo' : '/tmp/foo';

  setUp(() {
    fakeProcessManager = FakeProcessManager((String value) {});
    processRunner = ProcessRunner(
        processManager: fakeProcessManager,
        defaultWorkingDirectory: Directory(testPath));
  });

  tearDown(() {});

  group('Output Capture', () {
    test('runProcess works', () async {
      final calls = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], testPath):
            <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      await processRunner.runProcess(calls.keys.first.invocation);
      fakeProcessManager.verifyCalls(calls.keys);
    });
    test('runProcess returns correct output', () async {
      final calls = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], testPath):
            <ProcessResult>[
          ProcessResult(0, 0, 'output1', 'stderr1'),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      final result =
          await processRunner.runProcess(calls.keys.first.invocation);
      fakeProcessManager.verifyCalls(calls.keys);
      expect(result.stdout, equals('output1'));
      expect(result.stderr, equals('stderr1'));
      expect(result.output, equals('output1stderr1'));
    });
    test('runProcess fails properly', () async {
      final calls = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], ''):
            <ProcessResult>[
          ProcessResult(0, -1, 'output1', 'stderr1'),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      await expectLater(
          () => processRunner.runProcess(calls.keys.first.invocation),
          throwsException);
    });
    test('runProcess returns the failed results properly', () async {
      final calls = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], testPath):
            <ProcessResult>[
          ProcessResult(0, -1, 'output1', 'stderr1'),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      final result = await processRunner.runProcess(calls.keys.first.invocation,
          failOk: true);
      expect(result.stdout, equals('output1'));
      expect(result.stderr, equals('stderr1'));
      expect(result.output, equals('output1stderr1'));
    });
  });
}
