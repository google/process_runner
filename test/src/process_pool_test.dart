// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:process_runner/process_runner.dart';

import 'fake_process_manager.dart';

void main() {
  FakeProcessManager fakeProcessManager;
  ProcessRunner processRunner;
  ProcessPool processPool;

  setUp(() {
    fakeProcessManager = FakeProcessManager((String value) {});
    processRunner = ProcessRunner(
      processManager: fakeProcessManager,
      defaultWorkingDirectory: Directory('/tmp/foo'),
    );
    processPool = ProcessPool(processRunner: processRunner, printReport: null);
  });

  tearDown(() {});

  group('Output Capture', () {
    test('startWorkers works', () async {
      final Map<FakeInvocationRecord, List<ProcessResult>> calls =
          <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], '/tmp/foo'): <ProcessResult>[
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
      final Map<FakeInvocationRecord, List<ProcessResult>> calls =
          <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], '/tmp/foo'): <ProcessResult>[
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
    test('failed tests report results', () async {
      final Map<FakeInvocationRecord, List<ProcessResult>> calls =
          <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], '/tmp/foo'): <ProcessResult>[
          ProcessResult(0, -1, 'output1', 'stderr1'),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      final List<WorkerJob> jobs = <WorkerJob>[
        WorkerJob(<String>['command', 'arg1', 'arg2'], name: 'job 1'),
      ];
      final List<WorkerJob> completed = await processPool.runToCompletion(jobs);
      expect(completed.first.result.exitCode, equals(-1));
      expect(completed.first.result.stdout, equals('output1'));
      expect(completed.first.result.stderr, equals('stderr1'));
      expect(completed.first.result.output, equals('output1stderr1'));
    });
    test('Commands the throw exceptions report results', () async {
      fakeProcessManager = FakeProcessManager((String value) {}, commandsThrow: true);
      processRunner = ProcessRunner(processManager: fakeProcessManager);
      processPool = ProcessPool(processRunner: processRunner, printReport: null);
      final Map<FakeInvocationRecord, List<ProcessResult>> calls =
          <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], '/tmp/foo'): <ProcessResult>[
          ProcessResult(0, -1, 'output1', 'stderr1'),
        ],
      };
      fakeProcessManager.fakeResults = calls;
      final List<WorkerJob> jobs = <WorkerJob>[
        WorkerJob(<String>['command', 'arg1', 'arg2'], name: 'job 1'),
      ];
      final List<WorkerJob> completed = await processPool.runToCompletion(jobs);
      expect(completed.first.result, isNull);
      expect(completed.first.exception, isNotNull);
    });
  });
}
