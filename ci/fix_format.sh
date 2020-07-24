#!/bin/bash
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Make sure dartfmt is run on everything
echo "Fixing formatting..."

dartfmt_dirs=(lib test ci example)

exec dartfmt -w --line-length=100 "${dartfmt_dirs[@]}"

