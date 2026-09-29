#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
git_log="$test_tmp/git.log"
checkout="$test_tmp/checkout"
mkdir -p "$stub_bin" "$checkout"

cat >"$stub_bin/git" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_GIT_LOG"

[[ $1 == "-C" ]] || exit 1
shift 2

case "$1" in
  rev-parse)
    case "$2" in
      --is-inside-work-tree)
        [[ ${TEST_GIT_CHECKOUT:-yes} == "yes" ]] || exit 1
        echo true
        ;;
      --abbrev-ref)
        [[ ${TEST_GIT_UPSTREAM:-origin/quattro} != "none" ]] || exit 1
        echo "${TEST_GIT_UPSTREAM:-origin/quattro}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  diff)
    # Exit 0 (clean) unless TEST_GIT_DIRTY=yes, in which case exit 1
    if [[ ${TEST_GIT_DIRTY:-no} == "yes" ]]; then exit 1; fi
    exit 0
    ;;
  stash)
    # Record stash push/pop calls; always succeed so the test can assert ordering
    ;;
  pull)
    # TEST_GIT_PULL_FF_FAIL makes the --ff-only attempt exit 128 (git's
    # "not possible to fast-forward"), forcing the script's fallback to a
    # plain merge pull. The fallback itself always succeeds.
    if [[ $2 == "--ff-only" ]]; then
      [[ $2 == "--ff-only" ]] && [[ $3 == "--no-rebase" ]] || exit 1
      if [[ ${TEST_GIT_PULL_FF_FAIL:-no} == "yes" ]]; then exit 128; fi
    else
      [[ $2 == "--no-rebase" ]] || exit 1
    fi
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/git"

run_dev_update() {
  OMARCHY_PATH="$1" \
    TEST_GIT_LOG="$git_log" \
    TEST_GIT_DIRTY="${2:-no}" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-update-dev"
}

: >"$git_log"
run_dev_update /usr/share/omarchy
[[ ! -s $git_log ]] || fail "package-backed updates do not invoke git" "$(cat "$git_log")"
pass "package-backed updates skip the dev checkout step"

: >"$git_log"
run_dev_update "$checkout" no
grep -Fx -- "-C $checkout pull --ff-only --no-rebase" "$git_log" >/dev/null ||
  fail "dev checkout update pulls its upstream with fast-forward only and no rebase" "$(cat "$git_log")"
grep -q 'stash' "$git_log" &&
  fail "clean tree does not stash before pull" "$(cat "$git_log")"
pass "clean tree is pulled with --ff-only --no-rebase and not stashed"

: >"$git_log"
run_dev_update "$checkout" yes
grep -Fx -- "-C $checkout stash push -u -m omarchy update" "$git_log" >/dev/null ||
  fail "dirty tree stashes before pulling" "$(cat "$git_log")"
grep -Fx -- "-C $checkout pull --ff-only --no-rebase" "$git_log" >/dev/null ||
  fail "dirty tree is pulled after stashing" "$(cat "$git_log")"
grep -Fx -- "-C $checkout stash pop" "$git_log" >/dev/null ||
  fail "dirty tree restores the stash after pulling" "$(cat "$git_log")"
pass "dirty tree is stashed, pulled, and restored"

# A diverged local branch (commits upstream does not have) defeats
# --ff-only. The script must fall back to a plain merge pull instead of
# aborting the update with "Not possible to fast-forward".
: >"$git_log"
if ! TEST_GIT_PULL_FF_FAIL=yes run_dev_update "$checkout" no >"$test_tmp/diverge.out" 2>"$test_tmp/diverge.err"; then
  fail "diverged dev checkout does not abort the update" "$(cat "$test_tmp/diverge.err")"
fi
grep -Fx -- "-C $checkout pull --ff-only --no-rebase" "$git_log" >/dev/null ||
  fail "diverged checkout still tries fast-forward first" "$(cat "$git_log")"
grep -Fx -- "-C $checkout pull --no-rebase" "$git_log" >/dev/null ||
  fail "diverged checkout falls back to a plain merge pull" "$(cat "$git_log")"
pass "diverged dev checkout falls back to a plain merge pull instead of aborting"

# A dirty tree that also diverges must not lose the stash pop: stash, then
# attempt ff-only (fail), then plain pull, then pop.
: >"$git_log"
if ! TEST_GIT_PULL_FF_FAIL=yes run_dev_update "$checkout" yes >"$test_tmp/diverge_dirty.out" 2>"$test_tmp/diverge_dirty.err"; then
  fail "diverged dirty checkout does not abort the update" "$(cat "$test_tmp/diverge_dirty.err")"
fi
grep -Fx -- "-C $checkout stash push -u -m omarchy update" "$git_log" >/dev/null ||
  fail "diverged dirty tree still stashes before pulling" "$(cat "$git_log")"
grep -Fx -- "-C $checkout stash pop" "$git_log" >/dev/null ||
  fail "diverged dirty tree restores the stash after the fallback pull" "$(cat "$git_log")"
pass "diverged dirty tree is stashed, merged, and restored"

: >"$git_log"
TEST_GIT_UPSTREAM=none run_dev_update "$checkout"
if grep -q ' pull ' "$git_log"; then
  fail "dev checkout without an upstream is not pulled" "$(cat "$git_log")"
fi
pass "dev checkout without an upstream is skipped safely"

: >"$git_log"
if TEST_GIT_CHECKOUT=no run_dev_update "$checkout" >"$test_tmp/invalid.out" 2>"$test_tmp/invalid.err"; then
  fail "invalid dev checkout fails the update"
fi
grep -F "OMARCHY_PATH is not a git checkout: $checkout" "$test_tmp/invalid.err" >/dev/null ||
  fail "invalid dev checkout reports the configured path" "$(cat "$test_tmp/invalid.err")"
pass "invalid dev checkout fails with a useful error"

grep -qE '^ *omarchy-update-dev$' "$ROOT/bin/omarchy-update" ||
  fail "top-level update includes the dev checkout step"
pass "top-level update includes the dev checkout step"
