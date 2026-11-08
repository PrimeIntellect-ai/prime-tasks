#!/bin/bash
set -uo pipefail

WORKDIR=/rustfmt
TEST_FILES=(tests/target/issue_5691.rs)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
formatted=$(perl -0pe 's/\]:,\n\{/\]:, {/g' tests/target/issue_5691.rs | cargo run --quiet --bin rustfmt -- --emit stdout --config error_on_unformatted=false)
format_status=$?
status=0
if test "$format_status" -eq 0; then :; else printf '%s\n' 'FAIL: formatter could not produce valid output'; status=1; fi
if printf '%s\n' "$formatted" | grep -Fq 'A block comment in a body containing other comment styles.'; then :; else printf '%s\n' 'FAIL: block comment disappeared'; status=1; fi
if printf '%s\n' "$formatted" | grep -Fq 'A line comment following the block comment.'; then :; else printf '%s\n' 'FAIL: line comment disappeared'; status=1; fi
if printf '%s\n' "$formatted" | grep -Fq 'A doc comment preceding a field.'; then :; else printf '%s\n' 'FAIL: doc comment disappeared'; status=1; fi
if test "$(printf '%s\n' "$formatted" | grep -F -c 'num_slots!(C)')" -eq 1; then :; else printf '%s\n' 'FAIL: C where-clause expression was duplicated'; status=1; fi
if test "$(printf '%s\n' "$formatted" | grep -F -c 'num_slots!(D)')" -eq 1; then :; else printf '%s\n' 'FAIL: D where-clause expression was duplicated'; status=1; fi
if printf '%s\n' "$formatted" | grep -Fq 'A block comment in the empty reported body.'; then :; else printf '%s\n' 'FAIL: empty-body block comment disappeared'; status=1; fi
if printf '%s\n' "$formatted" | grep -Fq 'A line comment in the empty reported body.'; then :; else printf '%s\n' 'FAIL: empty-body line comment disappeared'; status=1; fi
test "$status" -eq 0 && cargo test -- --format=pretty
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
