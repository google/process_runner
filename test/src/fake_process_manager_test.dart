// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:process_runner/process_runner.dart';
import 'package:process_runner/test/fake_process_manager.dart';
import 'package:test/test.dart' hide TypeMatcher, isInstanceOf;

void main() {
  group('FakeProcessManager', () {
    final stdinCaptured = <String>[];
    void captureStdin(String item) {
      stdinCaptured.add(item);
    }

    late MemoryFileSystem fs;
    late FakeProcessManager processManager;
    late ProcessRunner processRunner;

    setUp(() async {
      fs = MemoryFileSystem(
          style: Platform.isWindows
              ? FileSystemStyle.windows
              : FileSystemStyle.posix);
      processManager = FakeProcessManager(captureStdin);
      processRunner = ProcessRunner(
          processManager: processManager,
          defaultWorkingDirectory: fs.currentDirectory);
    });

    tearDown(() async {
      stdinCaptured.clear();
    });

    test('fakes processes', () async {
      processManager.fakeResults = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(
          <String>['command', 'arg1', 'arg2'],
          workingDirectory: fs.currentDirectory.path,
        ): <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
        FakeInvocationRecord(
          <String>['command2', 'arg1', 'arg2'],
          workingDirectory: fs.currentDirectory.path,
        ): <ProcessResult>[
          ProcessResult(0, 0, 'output2', ''),
        ],
      };
      var result =
          await processRunner.runProcess(<String>['command', 'arg1', 'arg2']);
      expect(result.stdout, equals('output1'));
      result =
          await processRunner.runProcess(<String>['command2', 'arg1', 'arg2']);
      expect(result.stdout, equals('output2'));
      processManager.verifyCalls(<FakeInvocationRecord>[
        FakeInvocationRecord(
          <String>['command', 'arg1', 'arg2'],
          workingDirectory: fs.currentDirectory.path,
        ),
        FakeInvocationRecord(
          <String>['command2', 'arg1', 'arg2'],
          workingDirectory: fs.currentDirectory.path,
        ),
      ]);
    });
    test('distinguishes commands by working directory', () async {
      processManager.fakeResults = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(
          <String>['command', 'arg'],
          workingDirectory: Directory('wd1').absolute.path,
        ): <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
        FakeInvocationRecord(
          <String>['command', 'arg'],
          workingDirectory: Directory('wd2').absolute.path,
        ): <ProcessResult>[
          ProcessResult(0, 0, 'output2', ''),
        ],
      };
      var result = await processRunner.runProcess(
        <String>['command', 'arg'],
        workingDirectory: Directory('wd1'),
      );
      expect(result.stdout, equals('output1'));
      result = await processRunner.runProcess(
        <String>['command', 'arg'],
        workingDirectory: Directory('wd2'),
      );
      expect(result.stdout, equals('output2'));
      processManager.verifyCalls(<FakeInvocationRecord>[
        FakeInvocationRecord(
          <String>['command', 'arg'],
          workingDirectory: Directory('wd1').absolute.path,
        ),
        FakeInvocationRecord(
          <String>['command', 'arg'],
          workingDirectory: Directory('wd2').absolute.path,
        ),
      ]);
    });
    test('distinguishes commands by runInShell', () async {
      processManager.fakeResults = <FakeInvocationRecord, List<ProcessResult>>{
        FakeInvocationRecord(
          <String>['command', 'arg'],
          workingDirectory: fs.currentDirectory.path,
          runInShell: true,
        ): <ProcessResult>[
          ProcessResult(0, 0, 'output1', ''),
        ],
        FakeInvocationRecord(
          <String>['command', 'arg'],
          workingDirectory: fs.currentDirectory.path,
          runInShell: false,
        ): <ProcessResult>[
          ProcessResult(0, 0, 'output2', ''),
        ],
      };
      var result = await processRunner.runProcess(
        <String>['command', 'arg'],
        runInShell: true,
      );
      expect(result.stdout, equals('output1'));
      result = await processRunner.runProcess(
        <String>['command', 'arg'],
        runInShell: false,
      );
      expect(result.stdout, equals('output2'));
      processManager.verifyCalls(<FakeInvocationRecord>[
        FakeInvocationRecord(
          <String>['command', 'arg'],
          workingDirectory: fs.currentDirectory.path,
          runInShell: true,
        ),
        FakeInvocationRecord(
          <String>['command', 'arg'],
          workingDirectory: fs.currentDirectory.path,
          runInShell: false,
        ),
      ]);
    });
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

    test('run throws when commandsThrow is true', () async {
      processManager = FakeProcessManager(captureStdin, commandsThrow: true);
      expect(
        () async => await processManager.run(<String>['command']),
        throwsA(isA<ProcessException>()),
      );
    });

    test('runSync throws when commandsThrow is true', () async {
      processManager = FakeProcessManager(captureStdin, commandsThrow: true);
      expect(
        () => processManager.runSync(<String>['command']),
        throwsA(isA<ProcessException>()),
      );
    });

    test('start throws when commandsThrow is true', () async {
      processManager = FakeProcessManager(captureStdin, commandsThrow: true);
      expect(
        () async => await processManager.start(<String>['command']),
        throwsA(isA<ProcessException>()),
      );
    });
  });
}
