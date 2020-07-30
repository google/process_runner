#!/bin/bash
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# This script checks to make sure that the package *could* be published. It
# doesn't actually publish anything.

# Fast fail the script on failures.
set -e


# So cd doesn't print the path it changes to.
unset CDPATH

# So that developers can run this script from anywhere and it will work as
# expected.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

function error() {
  echo "$@" 1>&2
}

function check_publish() {
  echo -n "Checking that package can be published."
  if (cd "$REPO_DIR" && pub publish --dry-run > /dev/null); then
    echo "Package package is able to be published."
  else
    error "FAIL: The package failed the publishing check."
    return 1
  fi
  return 0
}

check_publish
