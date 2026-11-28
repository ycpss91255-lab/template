#!/usr/bin/env bats
#
# Guards which workflow owns the schedule.
#
# GitHub disables a workflow that carries a `schedule:` trigger once a
# public repo has been quiet for 60 days -- the whole workflow, not just
# the schedule. While ci.yaml carried it, that silently stopped the PR and
# push runs too (#28). The schedule lives in ci-weekly.yaml, which only
# calls ci.yaml, so the PR checks cannot be disabled with it.

bats_require_minimum_version 1.5.0

setup() {
  bats_load_library "bats-support"
  bats_load_library "bats-assert"
  WF="${BATS_TEST_DIRNAME}/../../.github/workflows"
}

# _triggers <file>
#   The trigger names under the top-level `on:`, one per line.
_triggers() {
  awk '/^on:/ { on = 1; next }
       /^[^[:space:]#]/ { on = 0 }
       on && match($0, /^  [a-z_]+:/) { print substr($0, 3, RLENGTH - 3) }' "$1"
}

# _jobs <file>
#   The job ids under the top-level `jobs:`, one per line.
_jobs() {
  awk '/^jobs:/ { on = 1; next }
       /^[^[:space:]#]/ { on = 0 }
       on && match($0, /^  [A-Za-z0-9_-]+:/) { print substr($0, 3, RLENGTH - 3) }' "$1"
}

@test "ci.yaml carries no schedule, so inactivity cannot disable the PR checks" {
  run _triggers "${WF}/ci.yaml"
  assert_success
  refute_line "schedule"
}

@test "ci.yaml still runs on push, pull_request, dispatch and call" {
  run _triggers "${WF}/ci.yaml"
  assert_success
  assert_line "push"
  assert_line "pull_request"
  assert_line "workflow_dispatch"
  assert_line "workflow_call"
}

@test "ci.yaml keeps the job id that branch protection requires, and runs this spec" {
  run _jobs "${WF}/ci.yaml"
  assert_success
  assert_line "test"
  # A `name:` on the job would rename the check that branch protection waits for.
  run awk '/^  test:/ { on = 1; next } /^  [A-Za-z0-9_-]+:/ { on = 0 } on && /^    name:/' "${WF}/ci.yaml"
  assert_output ""
  run grep -c 'test/integration/workflow_triggers_spec\.bats' "${WF}/ci.yaml"
  assert_output "1"
}

@test "ci-weekly.yaml owns the schedule and nothing a PR needs" {
  run _triggers "${WF}/ci-weekly.yaml"
  assert_success
  assert_line "schedule"
  refute_line "pull_request"
  refute_line "push"
}

@test "ci-weekly.yaml only calls ci.yaml, so the steps have one definition" {
  run _jobs "${WF}/ci-weekly.yaml"
  assert_success
  assert_output "ci"
  run grep -cE '^    uses: \./\.github/workflows/ci\.yaml$' "${WF}/ci-weekly.yaml"
  assert_output "1"
  run grep -cE '^ +(run|steps):' "${WF}/ci-weekly.yaml"
  assert_output "0"
}

@test "no workflow mixes a schedule with the triggers a PR or push needs" {
  local f
  for f in "${WF}"/*.yaml "${WF}"/*.yml; do
    [[ -e "${f}" ]] || continue
    run _triggers "${f}"
    assert_success
    if [[ "${output}" == *schedule* ]]; then
      refute_line "pull_request"
      refute_line "pull_request_target"
      refute_line "push"
    fi
  done
}

@test "ci.yaml runs on merge_group and has a ci-rollup job for the merge queue" {
  run _triggers "${WF}/ci.yaml"
  assert_success
  assert_line "merge_group"
  run _jobs "${WF}/ci.yaml"
  assert_success
  assert_line "ci-rollup"
}
