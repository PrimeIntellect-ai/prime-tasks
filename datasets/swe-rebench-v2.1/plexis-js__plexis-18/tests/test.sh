#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/plexis
TEST_FILES=(packages/plexis/test/__snapshots__/index.js.snap packages/toLower/test/index.js)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/node_modules/@plexis/to-lower"
cp packages/toLower/package.json "$tmpdir/node_modules/@plexis/to-lower/package.json"
cat > "$tmpdir/api-array-serializer.js" <<'SERIALIZER'
module.exports = {
  test(value) {
    return Array.isArray(value) && value.includes('toPred') && value.includes('toLower');
  },
  print(value, serialize) {
    return `Array [\n${[...value].sort().map(item => `  ${serialize(item)}`).join(',\n')}\n]`;
  }
};
SERIALIZER
npx babel packages/toLower/src --out-dir "$tmpdir/node_modules/@plexis/to-lower/dist" --root-mode upward
npx jest --verbose --no-colors --passWithNoTests --snapshotSerializers="$tmpdir/api-array-serializer.js" --moduleNameMapper="{\"^@plexis/to-lower$\":\"$tmpdir/node_modules/@plexis/to-lower\",\"^@plexis/to-pred$\":\"<rootDir>/packages/toPred/src/index.js\",\"^@plexis/to-succ$\":\"<rootDir>/packages/toSucc/src/index.js\",\"^@plexis/to-title$\":\"<rootDir>/packages/toTitle/src/index.js\",\"^@plexis/without-diacritics$\":\"<rootDir>/packages/withoutDiacritics/src/index.js\",\"^plexis$\":\"<rootDir>/packages/plexis/src/index.js\"}"
result=$?
rm -rf "$tmpdir"
test "$result" -eq 0
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
