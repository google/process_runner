# Change Log for `process_runner`

## 2.0.1

* Modified the package structure to get credit for having an example
* Moved sub-libraries into lib/src directory to hide them from dartdoc.
* Updated example documentation.

## 2.0.0

* Breaking change to modify the stderr, stdout, and output members of
  `ProcessRunnerResult` so that they return pre-decoded `String`s instead of
  `List<int>`s. Added `stderrRaw`, `stdoutRaw`, and `outputRaw` members that
  return the original `List<int>` values. Decoded strings are decoded by a new
  `decoder` optional argument which uses `SystemEncoder` by default.

* Breaking change to modify the `stdin` member of `WorkerJob` so that it is a
  `Stream<String>` instead of `Stream<List<int>>`, and a new `stdinRaw` method
  that is a `Stream<List<int>>`. Added an `encoder` attribute to `ProcessRunner`
  that provides the encoding for the `stdin` stream, as well as the default
  decoding for results.

* Added `ProcessPool.runToCompletion` convenience function to provide a simple
  interface that just delivers the final results, without dealing with streams.

* Added more tests.

## 1.0.0

* Initial version
