#!/bin/bash
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Fast fail the script on failures.
set -e

# This script checks to make sure that each of the plugins *could* be published.
# It doesn't actually publish anything.

unset CDPATH

# So that developers can run this script from anywhere and it will work as
# expected.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

function format() {
  dartfmt_dirs=(lib test ci example)
  (cd "$REPO_DIR" && dartfmt --line-length=100 "$@" ${dartfmt_dirs[@]})
}

# Make sure dartfmt is run on everything
function check_format() {
  echo "Checking dartfmt..."
  local needs_dartfmt="$(format -n "$@")"
  if [[ -n "$needs_dartfmt" ]]; then
    echo "FAILED"
    echo "$needs_dartfmt"
    echo ""
    echo "Fix formatting with: ci/format.sh --fix"
    exit 1
  fi
  echo "PASSED"
}

function fix_formatting() {
  echo "Fixing formatting..."
  format -w "$@"
}

if [[ "$1" == "--fix" ]]; then
  shift
  fix_formatting "$@"
else
  check_format "$@"
fi
