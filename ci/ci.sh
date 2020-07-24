#!/bin/bash
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Make sure dartfmt is run on everything
echo "Checking dartfmt..."
dartfmt_dirs=(lib test ci example)
needs_dartfmt="$(dartfmt -n --line-length=100 ${dartfmt_dirs[@]})"
if [[ -n "$needs_dartfmt" ]]; then
  echo "FAILED"
  echo "$needs_dartfmt"
  echo ""
  echo "Fix formatting with: ci/fix_format.sh"
  exit 1
fi
echo "PASSED"

# Make sure we pass the analyzer
echo "Checking dartanalyzer..."
fails_analyzer="$(find lib test ci -name "*.dart" | xargs dartanalyzer --options analysis_options.yaml)"
if [[ "$fails_analyzer" == *"[error]"* ]]; then
  echo "FAILED"
  echo "$fails_analyzer"
  exit 1
fi
echo "PASSED"

# Fast fail the script on failures.
set -e

# Run the tests.
pub run --enable-experiment=non-nullable test
