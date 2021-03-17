// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This example shows how to send a bunch of jobs to ProcessPool for processing.
//
// This example program is actually pretty useful even if you don't use
// process_runner for your Dart project. It can speed up processing of a bunch
// of single-threaded CPU-intensive commands by a multple of the number of
// processor cores you have (modulo being disk/network bound, of course).

import 'dart:io';

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

String usage() {
  return '''
main.dart [flags]
    --[no-]help           Print help.
    --[no-]report         Print progress on the jobs while running.
-w, --workers             Specify the number of workers jobs to run simultanously. Defaults to the number of processors on the machine.
-d, --workingDirectory    Specify the working directory to run on
                          (defaults to ".")
-c, --cmd                 Specify a command to add to the commands to be run. Entire command must be quoted by the shell. Commands specified with this option run before those specified with --cmdFile
-f, --file                Specify the name of a file to read commands from, one per line, as they would appear on the command line, with spaces escaped or quoted. Specify "-" to read from stdin.
                          (defaults to "-")
''';
}

String? findOption(String option, List<String> args) {
  for (int i = 0; i < args.length - 1; ++i) {
    if (args[i] == option) {
      return args[i + 1];
    }
  }
  return null;
}

Iterable<String> findAllOptions(String option, List<String> args) sync* {
  for (int i = 0; i < args.length - 1; ++i) {
    if (args[i] == option) {
      yield args[i + 1];
    }
  }
}

Future<void> main(List<String> args) async {
  // Parse args without ArgParser until ArgParser is null-safe.
  if (args.contains('--help')) {
    print('main.dart [flags]');
    print(usage());
    exit(0);
  }

  final bool printReport = args.contains('--report');
  // If the numWorkers is set to null, then the ProcessPool will automatically
  // select the number of processes based on how many CPU cores the machine has.
  final int? numWorkers = int.tryParse(findOption('workers', args) ?? '');
  final Directory workingDirectory = Directory(findOption('workingDirectory', args) ?? '.');
  final List<String> cmds = findAllOptions('cmd', args).toList();

  // Collect the commands to be run from the command file.
  final String commandFile = findOption('file', args) ?? '-';
  List<String> fileCommands = <String>[];
  // Read from stdin if the --file option is set to '-'.
  if (commandFile == '-') {
    String? line = stdin.readLineSync();
    while (line != null) {
      fileCommands.add(line);
      line = stdin.readLineSync();
    }
  } else {
    // Read the commands from a file.
    final File cmdFile = File(commandFile);
    if (!cmdFile.existsSync()) {
      print('Command file "$commandFile" doesn\'t exist.');
      exit(1);
    }
    fileCommands = cmdFile.readAsLinesSync();
  }

  // Collect all the commands, both from the input file, and from the command
  // line. The command line commands come first (although they could all be
  // executed simultaneously, depending on the number of workers, and number of
  // commands).
  final List<String> commands = <String>[
    ...cmds,
    ...fileCommands,
  ];

  // Split each command entry into a list of strings, taking into account some
  // simple quoting and escaping.
  final List<List<String>> splitCommands = commands.map<List<String>>(splitIntoArgs).toList();

  final ProcessPool pool = ProcessPool(
    numWorkers: numWorkers,
    printReport: printReport ? ProcessPool.defaultPrintReport : null,
  );
  final List<WorkerJob> jobs = splitCommands.map<WorkerJob>((List<String> command) {
    return WorkerJob(command, workingDirectory: workingDirectory);
  }).toList();
  await for (final WorkerJob done in pool.startWorkers(jobs)) {
    if (printReport) {
      print('\nFinished job ${done.name}');
    }
    stdout.write(done.result.stdout);
  }
}
