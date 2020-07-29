// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:process_runner/process_runner.dart';

import 'fake_process_manager.dart';

// TODO(gspencergoog): Implement tests.
void main() {
  FakeProcessManager fakeProcessManager = FakeProcessManager((String value) {});
  ProcessRunner processRunner = ProcessRunner(processManager: fakeProcessManager);

  setUp(() {
    fakeProcessManager = FakeProcessManager((String value) {});
    processRunner = ProcessRunner(processManager: fakeProcessManager);
  });

  tearDown(() {});

  group('Ouput Capture', () {
    test('runProcess works', () async {
      final Map<List<String>, List<ProcessResult>> calls = <List<String>, List<ProcessResult>>{
        <String>['command', 'arg1', 'arg2']: <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      await processRunner.runProcess(calls.keys.first);
      fakeProcessManager.verifyCalls(calls.keys);
    });
    test('runProcess returns correct output', () async {
      final Map<List<String>, List<ProcessResult>> calls = <List<String>, List<ProcessResult>>{
        <String>['command', 'arg1', 'arg2']: <ProcessResult>[
          ProcessResult(0, 0, 'output1', 'stderr1'),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      final ProcessRunnerResult result = await processRunner.runProcess(calls.keys.first);
      fakeProcessManager.verifyCalls(calls.keys);
      expect(result.stdout, equals('output1'));
      expect(result.stderr, equals('stderr1'));
      expect(result.output, equals('output1stderr1'));
    });
    test('runProcess fails properly', () async {
      final Map<List<String>, List<ProcessResult>> calls = <List<String>, List<ProcessResult>>{
        <String>['command', 'arg1', 'arg2']: <ProcessResult>[
          ProcessResult(0, -1, 'output1', 'stderr1'),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      expectLater(() => processRunner.runProcess(calls.keys.first), throwsException);
    });
  });
}
