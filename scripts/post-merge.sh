#!/bin/bash
set -e

# pluma is a native macOS Swift project — nothing can be built or installed
# in the Replit (Linux) environment. Builds happen on a Mac via:
#   xcodegen generate && xcodebuild -project Pluma.xcodeproj -scheme Pluma build
# This script exists so post-merge setup succeeds after task merges.
echo "No post-merge setup needed (macOS Swift project; build on a Mac)."
