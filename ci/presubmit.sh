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

cd "$SCRIPT_DIR"

./setup.sh > /dev/null 2>&1
./analyze.sh && ./format.sh && ./test.sh && ./check_publish.sh