#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/nickel
TEST_FILES=(cli/tests/snapshot/snapshots/snapshot__eval_stderr_array_range_reversed_indices.ncl.snap cli/tests/snapshot/snapshots/snapshot__eval_stderr_array_range_step_negative_step.ncl.snap)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
export RUST_TEST_THREADS=1
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
set -e
cargo build --package nickel-lang-cli
check_nickel_eval() {
  source="$1"
  expected="$2"
  exact="${3:-no}"
  output="$(printf '%s\n' "$source" | target/debug/nickel eval 2>&1)" || true
  if [ "$exact" = yes ]; then
    printf '%s\n' "$output" | grep -F -x -- "$expected" >/dev/null || {
      printf 'Expected exact Nickel output line: %s\nActual output:\n%s\n' "$expected" "$output" >&2
      return 1
    }
  elif ! printf '%s\n' "$output" | grep -F -- "$expected" >/dev/null; then
    printf 'Expected Nickel output to contain: %s\nActual output:\n%s\n' "$expected" "$output" >&2
    return 1
  fi
}
check_nickel_eval "std.array.try_fold_left (fun acc x => 'Ok (acc * 10 + x)) 0 [1, 2, 3]" "'Ok 123" yes
check_nickel_eval "std.array.try_fold_left (fun acc x => 'Ok (acc + x)) 42 []" "'Ok 42" yes
check_nickel_eval "std.array.try_fold_left (fun acc x => if x == 2 then 'Error \"stop\" else if x == 3 then std.seq (1 / 0) ('Ok acc) else 'Ok (acc + x)) 0 [1, 2, 3]" "'Error \"stop\"" yes
check_nickel_eval 'std.array.range 1 0' 'invalid range'
check_nickel_eval 'std.array.range_step 0 10 (-1)' 'invalid range step'
cargo test --package nickel-lang-* -- --nocapture --skip check_snapshots_cli_tests_snapshot_inputs_errors_array_range_reversed_indices_ncl --skip check_snapshots_cli_tests_snapshot_inputs_errors_array_range_step_negative_step_ncl
HARBOR_TEST_CMD_EOF

V=/logs/verifier
mkdir -p "$V"
echo 0 > "$V/reward.txt"
cd "$WORKDIR"
EXCLUDES=(.gitmodules '*.tar.gz' '*.tgz' '*.zip' '*.rej')

apply_patch() (
  set +eu +o pipefail
  git reset -q || true
  git update-index -q --refresh || true
  ex=()
  for e in "${EXCLUDES[@]}"; do ex+=("--exclude=$e"); done
  apply=(git apply --verbose "${ex[@]}" --whitespace=nowarn)
  "${apply[@]}" "$1" 2>&1 && exit 0
  keep=()
  while IFS= read -r path; do
    glob=$(printf '%s' "$path" | sed 's/[][*?\\]/\\&/g')
    git apply --summary --include="$glob" "$1" | grep -q "^ create mode" &&
      [ -z "$(git apply --check -R --whitespace=nowarn --include="$glob" "$1" 2>&1)" ] && keep+=("--exclude=$glob")
  done < <(LC_ALL=C "${apply[@]}" --check "$1" 2>&1 | sed -n 's/^error: \(.*\): already exists in working directory$/\1/p')
  "${apply[@]}" "${keep[@]}" "$1" 2>&1 && exit 0
  [ -z "$(git apply --check -R --whitespace=nowarn "${ex[@]}" "$1" 2>&1)" ] && exit 0
  "${apply[@]}" "${keep[@]}" --reject "$1" 2>&1
  exit 1
)

if [ -s /logs/artifacts/model.patch ]; then
  if ! (EXCLUDES=(); apply_patch /logs/artifacts/model.patch) > "$V/model_patch_apply.log" 2>&1; then
    echo "MODEL_PATCH_APPLY_FAILED"
    cat "$V/model_patch_apply.log"
    exit 0
  fi
fi
for f in "${TEST_FILES[@]}"; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then git restore "$f" 2>/dev/null; else rm -f "$f"; fi
done
cp /tests/test.patch /tmp/test.patch
if ! apply_patch /tmp/test.patch > "$V/test_patch_apply.log" 2>&1; then
  echo "TEST_PATCH_APPLY_FAILED"
  cat "$V/test_patch_apply.log"
  exit 0
fi

export HARBOR_TEST_CMD="${HARBOR_TEST_CMD%$'\n'}"
bash -lc 'timeout -k 10 1800 bash -lc "$HARBOR_TEST_CMD"' 2>&1 | cat > "$V/test_output.log"
echo "test_cmd exit code: ${PIPESTATUS[0]}"

for PY in /opt/harbor-grader/python3 python3 python /opt/conda/bin/python3 ""; do
  PY=$(command -v "$PY" 2>/dev/null) && "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null && break
done
if [ -z "$PY" ]; then
  echo "GRADER_PYTHON_UNAVAILABLE: the image has no Python >= 3.8"
  exit 0
fi
if "$PY" -I -S /tests/grade.py /tests/config.json "$V/test_output.log" "$V/report.json" "$V/test_results.json"; then
  echo 1 > "$V/reward.txt"
fi
