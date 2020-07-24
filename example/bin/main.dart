// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:process_runner/process_runner.dart';

// This only works for escaped spaces and things in double or single quotes.
// This is just an example, modify to meet your own requirements.
List<String> splitIntoArgs(String args) {
  bool inQuote = false;
  bool inEscape = false;
  String quoteMatch = '';
  final List<String> result = <String>[];
  final List<String> currentArg = <String>[];
  for (int i = 0; i < args.length; ++i) {
    final String char = args[i];
    if (inEscape) {
      switch (char) {
        case 'n':
          currentArg.add('\n');
          break;
        case 't':
          currentArg.add('\t');
          break;
        case 'r':
          currentArg.add('\r');
          break;
        case 'b':
          currentArg.add('\b');
          break;
        default:
          currentArg.add(char);
          break;
      }
      inEscape = false;
      continue;
    }
    if (char == ' ' && !inQuote) {
      result.add(currentArg.join(''));
      currentArg.clear();
      continue;
    }
    if (char == r'\') {
      inEscape = true;
      continue;
    }
    if (inQuote) {
      if (char == quoteMatch) {
        inQuote = false;
        quoteMatch = '';
      } else {
        currentArg.add(char);
      }
      continue;
    }
    if (char == '"' || char == '"') {
      inQuote = !inQuote;
      quoteMatch = args[i];
      continue;
    }
    currentArg.add(char);
  }
  if (currentArg.isNotEmpty) {
    result.add(currentArg.join(''));
  }
  return result;
}

Future<void> main(List<String> args) async {
  final ArgParser parser = ArgParser();
  parser.addFlag('help', help: 'Print help.');
  parser.addFlag('report', help: 'Print progress on the jobs while running.', defaultsTo: false);
  parser.addOption('workers',
      help: 'Specify the number of workers jobs to run simultanously. Defaults '
          'to the number of processors on the machine.');
  parser.addOption('workingDirectory',
      help: 'Specify the working directory to run on', defaultsTo: '.');
  parser.addMultiOption('cmd',
      help: 'Specify a command to add to the commands to be run. Entire '
          'command must be quoted by the shell. Commands specified with this '
          'option run before those specified with --cmdFile');
  parser.addOption('cmdFile',
      help: 'Specify the name of a file to read commands from, one per line, as '
          'they would appear on the command line, with spaces escaped or '
          'quoted. Specify "-" to read from stdin.');
  final ArgResults flags = parser.parse(args);

  if (flags['help'] as bool) {
    print('main.dart [flags]');
    print(parser.usage);
    exit(0);
  }

  List<String> fileCommands = <String>[];
  if (flags['cmdFile'] != null) {
    if (flags['cmdFile'] == '-') {
      String line = stdin.readLineSync();
      while (line != null) {
        fileCommands.add(line);
        line = stdin.readLineSync();
      }
    } else {
      final File cmdFile = File(flags['cmdFile'] as String);
      if (!cmdFile.existsSync()) {
        print('Command file "$cmdFile" doesn\'t exist.');
        exit(1);
      }
      fileCommands = cmdFile.readAsLinesSync();
    }
  }
  final List<String> commands = <String>[
    ...flags['cmd'] as List<String>,
    ...fileCommands,
  ];
  final List<List<String>> splitCommands = commands.map<List<String>>(splitIntoArgs).toList();

  int numWorkers = int.parse((flags['workers'] as String) ?? '-1');
  numWorkers = numWorkers == -1 ? null : numWorkers;

  final bool printReport = (flags['report'] as bool) ?? false;

  final Directory workingDirectory = Directory((flags['workingDirectory'] as String) ?? '.');

  final ProcessPool pool = ProcessPool(
    numWorkers: numWorkers,
    printReport: printReport ? ProcessPool.defaultPrintReport : null,
  );
  final List<WorkerJob> jobs = splitCommands.map<WorkerJob>((List<String> command) {
    return WorkerJob(command.join(' '), command, workingDirectory: workingDirectory);
  }).toList();
  await for (final WorkerJob done in pool.startWorkers(jobs)) {
    if (printReport) {
      print('\nFinished job ${done.name}');
    }
  }
}
