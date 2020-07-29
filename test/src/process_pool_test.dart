// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:process_runner/process_runner.dart';

import 'fake_process_manager.dart';

void main() {
  FakeProcessManager fakeProcessManager = FakeProcessManager((String value) {});
  ProcessRunner processRunner = ProcessRunner(processManager: fakeProcessManager);
  ProcessPool processPool = ProcessPool(processRunner: processRunner);

  setUp(() {
    fakeProcessManager = FakeProcessManager((String value) {});
    processRunner = ProcessRunner(processManager: fakeProcessManager);
    processPool = ProcessPool(processRunner: processRunner, printReport: null);
  });

  tearDown(() {});

  group('Ouput Capture', () {
    test('startWorkers works', () async {
      final Map<List<String>, List<ProcessResult>> calls = <List<String>, List<ProcessResult>>{
        <String>['command', 'arg1', 'arg2']: <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      final List<WorkerJob> jobs = <WorkerJob>[
        WorkerJob(<String>['command', 'arg1', 'arg2'], name: 'job 1'),
      ];
      await for (final WorkerJob _ in processPool.startWorkers(jobs)) {}
      fakeProcessManager.verifyCalls(calls.keys);
    });
    test('runToCompletion works', () async {
      final Map<List<String>, List<ProcessResult>> calls = <List<String>, List<ProcessResult>>{
        <String>['command', 'arg1', 'arg2']: <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      final List<WorkerJob> jobs = <WorkerJob>[
        WorkerJob(<String>['command', 'arg1', 'arg2'], name: 'job 1'),
      ];
      await processPool.runToCompletion(jobs);
      fakeProcessManager.verifyCalls(calls.keys);
    });
  });
}
