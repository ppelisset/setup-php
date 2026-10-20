#!/usr/bin/env bash

# Exercise the real runner detection and PHP installer selection without installing PHP.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts="$script_dir/../../src/scripts"

if [ "${1:-}" = "--case" ]; then
  . "$scripts/unix.sh"
  eval "$(sed -n '/^add_php() {$/,/^}$/p' "$scripts/linux.sh")"

  # Model /proc and the runner registration; evaluate the real jq filter.
  readlink() {
    [ "${TEST_WORKER_READABLE:-true}" = "true" ] || return 1
    if [ "${TEST_WORKER_ANCESTOR:-true}" = "true" ]; then
      printf '%s\n' /runner/bin/Runner.Worker
    else
      printf '%s\n' /usr/bin/bash
    fi
  }
  awk() { printf '%s\n' 1; }
  jq() {
    [ "${TEST_CONFIG_READABLE:-true}" = "true" ] || return 1
    local registration="{\"AgentName\":\"${TEST_AGENT_NAME-${RUNNER_NAME:-}}\"}"
    command jq "${@:1:$#-1}" <<<"$registration"
  }
  uname() { printf '%s\n' "${TEST_ARCH:-x86_64}"; }
  check_ppa() { return 0; }
  sudo() {
    printf '%s\n' 'Unexpected sudo invocation' >&2
    exit 99
  }
  setup_cached_versions() { printf '%s\n' archive; }
  setup_old_versions() { printf '%s\n' old-archive; }
  setup_php_builder() { printf '%s\n' builder; }
  add_packaged_php() { printf '%s\n' packages; }
  switch_version() { :; }
  add_pecl() { :; }

  read_env
  set +x
  version="${TEST_PHP_VERSION:-8.2}"
  printf '%s:%s:' "$runner" "${builds_cache_warning:-false}"
  add_php
  exit
fi

failures=0
cases=0
check_case() {
  local name="$1" expected="$2" expected_status="$3" actual status
  shift 3
  cases=$((cases + 1))
  actual=$(env -i PATH="$PATH" \
    ID=ubuntu VERSION_ID=26.04 ImageOS=ubuntu26 ImageVersion=20261005.01 \
    RUNNER_ENVIRONMENT=self-hosted RUNNER_NAME=warp-test \
    WARPBUILD_RUNNER_VERIFICATION_TOKEN=test-marker \
    "$@" "$BASH" "$script_dir/runner.test.sh" --case 2>&1)
  status=$?
  if [ "$status" -eq "$expected_status" ] && [[ "$actual" == *"$expected"* && "$actual" != *test-marker* ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: expected status=%s, output=%s; got status=%s, output=%s\n' \
      "$name" "$expected_status" "$expected" "$status" "$actual"
    failures=$((failures + 1))
  fi
}

check_case 'WarpBuild uses archives automatically' 'github:true:archive' 0
check_case 'WarpBuild PHP 8.1' 'github:true:archive' 0 TEST_PHP_VERSION=8.1
check_case 'WarpBuild PHP 8.3' 'github:true:archive' 0 TEST_PHP_VERSION=8.3
check_case 'WarpBuild Ubuntu 22.04' 'github:true:archive' 0 VERSION_ID=22.04 ImageOS=ubuntu22
check_case 'WarpBuild Ubuntu 24.04' 'github:true:archive' 0 VERSION_ID=24.04 ImageOS=ubuntu24
check_case 'WarpBuild ARM64' 'github:true:archive' 0 TEST_ARCH=aarch64
check_case 'Explicit builds cache opt-in' 'github:true:archive' 0 use_builds_cache=true
check_case 'Legacy builds cache opt-in' 'github:true:archive' 0 use_package_cache=true
check_case 'Explicit GitHub runner on verified WarpBuild' 'github:true:archive' 0 runner=github
check_case 'Builds cache opt-out' 'self-hosted:false:packages' 0 use_builds_cache=false
check_case 'Legacy builds cache opt-out' 'self-hosted:false:packages' 0 use_package_cache=false
check_case 'Current option overrides legacy option' 'self-hosted:false:packages' 0 use_builds_cache=false use_package_cache=true
check_case 'Explicit self-hosted runner' 'self-hosted:false:packages' 0 runner=self-hosted
check_case 'Uppercase self-hosted runner' 'self-hosted:false:packages' 0 RUNNER=self-hosted
check_case 'Non-Ubuntu image' 'self-hosted:false:packages' 0 ID=debian
check_case 'Unsupported Ubuntu release' 'self-hosted:false:packages' 0 VERSION_ID=20.04 ImageOS=ubuntu20
check_case 'Unsupported architecture' 'self-hosted:false:packages' 0 TEST_ARCH=s390x
check_case 'Missing image metadata' 'self-hosted:false:packages' 0 ImageOS= ImageVersion=
check_case 'Mismatched image metadata' 'self-hosted:false:packages' 0 ImageOS=ubuntu24
check_case 'Container' 'self-hosted:false:packages' 0 CONTAINER=true
check_case 'act' 'self-hosted:false:packages' 0 ACT=true
check_case 'Missing WarpBuild marker' 'self-hosted:false:packages' 0 WARPBUILD_RUNNER_VERIFICATION_TOKEN=
check_case 'Unrecognized runner name' 'self-hosted:false:packages' 0 RUNNER_NAME=custom-runner
check_case 'Runner name does not match registration' 'self-hosted:false:packages' 0 TEST_AGENT_NAME=warp-another-runner
check_case 'Registration is unreadable' 'self-hosted:false:packages' 0 TEST_CONFIG_READABLE=false
check_case 'Worker is unreadable' 'self-hosted:false:packages' 0 TEST_WORKER_READABLE=false
check_case 'Worker is not an ancestor' 'self-hosted:false:packages' 0 TEST_WORKER_ANCESTOR=false
check_case 'GitHub-hosted runner' 'github:false:archive' 0 RUNNER_ENVIRONMENT=github-hosted RUNNER_NAME=HostedAgent WARPBUILD_RUNNER_VERIFICATION_TOKEN=
check_case 'GitHub-hosted runner opt-out' 'github:false:packages' 0 RUNNER_ENVIRONMENT=github-hosted RUNNER_NAME=HostedAgent WARPBUILD_RUNNER_VERIFICATION_TOKEN= use_builds_cache=false
check_case 'Blacksmith keeps opt-in' 'self-hosted:false:packages' 0 RUNNER_NAME=blacksmith-test WARPBUILD_RUNNER_VERIFICATION_TOKEN=
check_case 'Blacksmith opt-in still works' 'github:true:archive' 0 RUNNER_NAME=blacksmith-test WARPBUILD_RUNNER_VERIFICATION_TOKEN= use_builds_cache=true
check_case 'Depot opt-in still works' 'github:true:archive' 0 RUNNER_NAME=depot-test WARPBUILD_RUNNER_VERIFICATION_TOKEN= use_builds_cache=true
check_case 'Unverified runner cannot force GitHub mode' 'Runner set as github in self-hosted environment' 1 RUNNER_NAME=custom-runner WARPBUILD_RUNNER_VERIFICATION_TOKEN= runner=github
check_case 'Trace does not expose WarpBuild marker' 'github:true:archive' 0 SETUP_PHP_TRACE=1

check_ubicloud_case() {
  local name="$1" expected="$2"
  shift 2
  check_case "Ubicloud $name" "$expected" 0 \
    WARPBUILD_RUNNER_VERIFICATION_TOKEN= RUNNER_NAME=gr0123456789abcdefghjkmnpq \
    UBICLOUD_RUNTIME_TOKEN=test-marker UBICLOUD_CACHE_URL=https://console.ubicloud.com/runtime/github/ "$@"
}

check_ubicloud_case 'uses archives automatically' 'github:true:archive'
check_ubicloud_case 'PHP 8.1' 'github:true:archive' TEST_PHP_VERSION=8.1
check_ubicloud_case 'PHP 8.3' 'github:true:archive' TEST_PHP_VERSION=8.3
for release in 22 24 26; do
  check_ubicloud_case "Ubuntu $release.04 x64" 'github:true:archive' VERSION_ID="$release.04" ImageOS="ubuntu$release"
  check_ubicloud_case "Ubuntu $release.04 ARM64" 'github:true:archive' VERSION_ID="$release.04" ImageOS="ubuntu$release-arm64" TEST_ARCH=aarch64
done
check_ubicloud_case 'builds cache opt-in' 'github:true:archive' use_builds_cache=true
check_ubicloud_case 'builds cache opt-out' 'self-hosted:false:packages' use_builds_cache=false
check_ubicloud_case 'legacy builds cache opt-out' 'self-hosted:false:packages' use_package_cache=false
check_ubicloud_case 'explicit self-hosted runner' 'self-hosted:false:packages' runner=self-hosted
check_ubicloud_case 'uppercase self-hosted runner' 'self-hosted:false:packages' RUNNER=self-hosted
check_ubicloud_case 'missing runtime token' 'self-hosted:false:packages' UBICLOUD_RUNTIME_TOKEN=
check_ubicloud_case 'missing cache URL' 'self-hosted:false:packages' UBICLOUD_CACHE_URL=
check_ubicloud_case 'unrecognized runner name' 'self-hosted:false:packages' RUNNER_NAME=ubicloud-test
check_ubicloud_case 'truncated runner ID' 'self-hosted:false:packages' RUNNER_NAME=gr0123456789
check_ubicloud_case 'invalid runner ID alphabet' 'self-hosted:false:packages' RUNNER_NAME=gr0123456789abcdefgijkmnpq
check_ubicloud_case 'mismatched registration' 'self-hosted:false:packages' TEST_AGENT_NAME=gr0123456789abcdefghjkmnps
check_ubicloud_case 'unreadable registration' 'self-hosted:false:packages' TEST_CONFIG_READABLE=false
check_ubicloud_case 'no worker ancestor' 'self-hosted:false:packages' TEST_WORKER_ANCESTOR=false
check_ubicloud_case 'non-Ubuntu image' 'self-hosted:false:packages' ID=debian
check_ubicloud_case 'unsupported Ubuntu release' 'self-hosted:false:packages' VERSION_ID=20.04 ImageOS=ubuntu20
check_ubicloud_case 'missing image version' 'self-hosted:false:packages' ImageVersion=
check_ubicloud_case 'mismatched image release' 'self-hosted:false:packages' ImageOS=ubuntu24
check_ubicloud_case 'ARM64 image on x64' 'self-hosted:false:packages' ImageOS=ubuntu26-arm64
check_ubicloud_case 'unsupported architecture' 'self-hosted:false:packages' TEST_ARCH=s390x
check_ubicloud_case 'container' 'self-hosted:false:packages' CONTAINER=true
check_ubicloud_case 'act' 'self-hosted:false:packages' ACT=true
check_ubicloud_case 'trace does not expose runtime token' 'github:true:archive' SETUP_PHP_TRACE=1

printf '%s cases, %s failures\n' "$cases" "$failures"
[ "$failures" -eq 0 ]
