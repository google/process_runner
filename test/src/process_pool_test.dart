// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:process_runner/process_runner.dart';
import 'package:test/expect.dart';
import 'package:test/test.dart';

import 'fake_process_manager.dart';

void main() {
  late FakeProcessManager fakeProcessManager;
  late ProcessRunner processRunner;
  late ProcessPool processPool;
  final String testPath = Platform.isWindows ? r'C:\tmp\foo' : '/tmp/foo';

  setUp(() {
    fakeProcessManager = FakeProcessManager((String value) {});
    processRunner = ProcessRunner(
      processManager: fakeProcessManager,
      defaultWorkingDirectory: Directory(testPath),
    );
    processPool = ProcessPool(processRunner: processRunner, printReport: null);
  });

  test('startWorkers works', () async {
    final Map<FakeInvocationRecord, List<ProcessResult>> calls = <FakeInvocationRecord, List<ProcessResult>>{
      FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], testPath): <ProcessResult>[
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
    final Map<FakeInvocationRecord, List<ProcessResult>> calls = <FakeInvocationRecord, List<ProcessResult>>{
      FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], testPath): <ProcessResult>[
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
    final Map<FakeInvocationRecord, List<ProcessResult>> calls = <FakeInvocationRecord, List<ProcessResult>>{
      FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], testPath): <ProcessResult>[
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
  test('failed tests throw when failOk is false', () async {
    final Map<FakeInvocationRecord, List<ProcessResult>> calls = <FakeInvocationRecord, List<ProcessResult>>{
      FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, -1, 'output1', 'stderr1'),
      ],
    };
    fakeProcessManager.fakeResults = calls;
    final List<WorkerJob> jobs = <WorkerJob>[
      WorkerJob(<String>['command', 'arg1', 'arg2'], name: 'job 1', failOk: false),
    ];
    expect(() async {
      await processPool.runToCompletion(jobs);
    }, throwsException);
  });
  test('Commands that throw exceptions report results', () async {
    fakeProcessManager = FakeProcessManager((String value) {}, commandsThrow: true);
    processRunner = ProcessRunner(processManager: fakeProcessManager);
    processPool = ProcessPool(processRunner: processRunner, printReport: null);
    final Map<FakeInvocationRecord, List<ProcessResult>> calls = <FakeInvocationRecord, List<ProcessResult>>{
      FakeInvocationRecord(<String>['command', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, -1, 'output1', 'stderr1'),
      ],
    };
    fakeProcessManager.fakeResults = calls;
    final List<WorkerJob> jobs = <WorkerJob>[
      WorkerJob(<String>['command', 'arg1', 'arg2'], name: 'job 1'),
    ];
    final List<WorkerJob> completed = await processPool.runToCompletion(jobs);
    expect(completed.first.result, equals(ProcessRunnerResult.failed));
    expect(completed.first.exception, isNotNull);
  });

  test('Commands in task groups run in order, but parallel with other groups', () async {
    fakeProcessManager = FakeProcessManager((String value) {});
    processRunner = ProcessRunner(processManager: fakeProcessManager);
    processPool = ProcessPool(processRunner: processRunner, printReport: null);
    final Map<FakeInvocationRecord, List<ProcessResult>> calls = <FakeInvocationRecord, List<ProcessResult>>{
      FakeInvocationRecord(<String>['commandA1', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputA1', 'stderrA1'),
      ],
      FakeInvocationRecord(<String>['commandB1', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputB1', 'stderrB1'),
      ],
      FakeInvocationRecord(<String>['commandA2', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputA2', 'stderrA2'),
      ],
      FakeInvocationRecord(<String>['commandB2', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, -1, 'outputB2', 'stderrB2'),
      ],
      FakeInvocationRecord(<String>['commandA3', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputA3', 'stderrA3'),
      ],
      FakeInvocationRecord(<String>['commandB3', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputB3', 'stderrB3'),
      ],
    };
    fakeProcessManager.fakeResults = calls;
    final List<WorkerJobGroup> jobs = <WorkerJobGroup>[
      WorkerJobGroup(
        <WorkerJob>[
          WorkerJob(<String>['commandA1', 'arg1', 'arg2'], name: 'job A1'),
          WorkerJob(<String>['commandA2', 'arg1', 'arg2'], name: 'job A2'),
          WorkerJob(<String>['commandA3', 'arg1', 'arg2'], name: 'job A3'),
        ],
        name: 'Group A',
      ),
      WorkerJobGroup(
        <WorkerJob>[
          WorkerJob(<String>['commandB1', 'arg1', 'arg2'], name: 'job B1'),
          WorkerJob(<String>['commandB2', 'arg1', 'arg2'], name: 'job B2'),
          WorkerJob(<String>['commandB3', 'arg1', 'arg2'], name: 'job B3'),
        ],
        name: 'Group B',
      ),
    ];
    final List<WorkerJob> completed = await processPool.runToCompletion(jobs);
    expect(completed.length, equals(6));
    // Command B2 failed with -1, so B3 should also fail.
    expect(
      completed.where((WorkerJob job) => job.result.exitCode != 0).map((WorkerJob job) => job.name),
      unorderedEquals(<String>['job B2', 'job B3']),
    );
    expect(
      completed.where((WorkerJob job) => job.exception == null).map((WorkerJob job) => job.name),
      unorderedEquals(<String>['job A1', 'job B1', 'job A2', 'job A3']),
    );
    expect(
      completed.where((WorkerJob job) => job.result.exitCode == 0).map((WorkerJob job) => job.name),
      unorderedEquals(<String>['job B1', 'job A1', 'job A2', 'job A3']),
    );
    // Either group A or B can come first, but the individual group tasks should
    // be in order.
    expect(
      <String>[completed[0].name, completed[1].name],
      unorderedEquals(<String>['job A1', 'job B1']),
    );
    expect(
      <String>[completed[2].name, completed[3].name],
      unorderedEquals(<String>['job A2', 'job B2']),
    );
    expect(
      <String>[completed[4].name, completed[5].name],
      unorderedEquals(<String>['job A3', 'job B3']),
    );
  });
  test('Commands in task groups can depend on other groups', () async {
    fakeProcessManager = FakeProcessManager((String value) {});
    processRunner = ProcessRunner(processManager: fakeProcessManager);
    processPool = ProcessPool(processRunner: processRunner, printReport: null);
    final Map<FakeInvocationRecord, List<ProcessResult>> calls = <FakeInvocationRecord, List<ProcessResult>>{
      FakeInvocationRecord(<String>['commandA1', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputA1', 'stderrA1'),
      ],
      FakeInvocationRecord(<String>['commandB1', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputB1', 'stderrB1'),
      ],
      FakeInvocationRecord(<String>['commandA2', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputA2', 'stderrA2'),
      ],
      FakeInvocationRecord(<String>['commandB2', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, -1, 'outputB2', 'stderrB2'),
      ],
      FakeInvocationRecord(<String>['commandA3', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputA3', 'stderrA3'),
      ],
      FakeInvocationRecord(<String>['commandB3', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputB3', 'stderrB3'),
      ],
    };
    fakeProcessManager.fakeResults = calls;
    final WorkerJobGroup groupA = WorkerJobGroup(
      <DependentJob>[
        WorkerJob(<String>['commandA1', 'arg1', 'arg2'], name: 'job A1'),
        WorkerJob(<String>['commandA2', 'arg1', 'arg2'], name: 'job A2'),
        WorkerJob(<String>['commandA3', 'arg1', 'arg2'], name: 'job A3'),
      ],
      name: 'Group A',
    );
    final WorkerJobGroup groupB = WorkerJobGroup(
      <DependentJob>[
        WorkerJob(<String>['commandB1', 'arg1', 'arg2'], name: 'job B1'),
        WorkerJob(<String>['commandB2', 'arg1', 'arg2'], name: 'job B2'),
        WorkerJob(<String>['commandB3', 'arg1', 'arg2'], name: 'job B3'),
      ],
      name: 'Group B',
    );
    groupB.addDependency(groupA);
    final List<DependentJob> jobs = <DependentJob>[groupA, groupB];
    final List<WorkerJob> completed = await processPool.runToCompletion(jobs);
    expect(completed.length, equals(6));
    // Make sure they executed in the correct order.
    expect(completed.map<String>((WorkerJob job) => job.name),
        equals(<String>['job A1', 'job A2', 'job A3', 'job B1', 'job B2', 'job B3']));
    // Command B2 failed with -1, so B3 should also fail.
    expect(
      completed.where((WorkerJob job) => job.result.exitCode != 0).map((WorkerJob job) => job.name),
      unorderedEquals(<String>['job B2', 'job B3']),
    );
    expect(
      completed.where((WorkerJob job) => job.exception == null).map((WorkerJob job) => job.name),
      unorderedEquals(<String>['job A1', 'job B1', 'job A2', 'job A3']),
    );
    expect(
      completed.where((WorkerJob job) => job.result.exitCode == 0).map((WorkerJob job) => job.name),
      unorderedEquals(<String>['job B1', 'job A1', 'job A2', 'job A3']),
    );
  });
test("Jobs can't depend on themselves", () async {
    fakeProcessManager = FakeProcessManager((String value) {});
    processRunner = ProcessRunner(processManager: fakeProcessManager);
    processPool = ProcessPool(processRunner: processRunner, printReport: null);
    final Map<FakeInvocationRecord, List<ProcessResult>> calls = <FakeInvocationRecord, List<ProcessResult>>{
      FakeInvocationRecord(<String>['commandA1', 'arg1', 'arg2'], testPath): <ProcessResult>[
        ProcessResult(0, 0, 'outputA1', 'stderrA1'),
      ],
    };
    fakeProcessManager.fakeResults = calls;
    final WorkerJob job = WorkerJob(<String>['commandA1', 'arg1', 'arg2'], name: 'job A1');

    ProcessRunnerException? exception;
    try {
      job.addDependency(job);
    } on ProcessRunnerException catch (e) {
      exception = e;
    }
    expect(exception, isNotNull);
    expect(exception!.message, equals('A job cannot depend on itself'));
  });
}
