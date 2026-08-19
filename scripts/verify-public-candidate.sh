#!/bin/zsh
set -euo pipefail

verify_first_run=false
if (( $# > 1 )); then
  print -u2 "usage: verify-public-candidate.sh [--verify-first-run]"
  exit 64
fi
if (( $# == 1 )); then
  [[ "$1" == "--verify-first-run" ]] \
    || { print -u2 "usage: verify-public-candidate.sh [--verify-first-run]"; exit 64; }
  verify_first_run=true
fi

repository_root="${0:A:h:h}"
cd "$repository_root"
scripts/verify-public-repository.sh
scripts/verify-staged-runtime.sh
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
scripts/test-public-resource-gates.sh
scripts/verify-public-flavor.sh
scripts/test-public-swiftpm.sh
scripts/verify-generated-public-bundles.sh
if $verify_first_run; then
  scripts/build-and-run-open.sh --verify-first-run
fi

print "verify-public-candidate: staged runtime, Open build, tests, resources, and public boundaries passed"
