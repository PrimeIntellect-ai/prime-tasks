#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/material-bread
TEST_FILES=(src/Components/Chip/__snapshots__/Chip.test.js.snap src/Components/Drawer/DrawerItem/__snapshots__/DrawerItem.test.js.snap src/Components/Menu/MenuItem/__snapshots__/MenuItem.test.js.snap src/Components/RadioButton/__snapshots__/RadioButton.test.js.snap src/Components/Ripple/__snapshots__/Ripple.test.js.snap)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
node - <<'JS'
const fs = require('fs');
const childProcess = require('child_process');
const result = childProcess.spawnSync('./node_modules/.bin/jest', ['--showConfig'], { encoding: 'utf8' });
const config = JSON.parse(result.stdout).configs[0];
for (const key of ['moduleNameMapper', 'transform']) {
  if (Array.isArray(config[key])) config[key] = Object.fromEntries(config[key]);
}
delete config.detectLeaks;
delete config.detectOpenHandles;
config.snapshotSerializers = ['/tmp/rebench-testid-serializer.js'];
fs.writeFileSync('/tmp/rebench-jest-config.json', JSON.stringify(config));
fs.writeFileSync('/tmp/rebench-testid-serializer.js', `module.exports = {
  test(value) {
    return value && typeof value === 'object' && value.props && typeof value.props.testID === 'string' && !value.__normalizedTestID;
  },
  print(value, serialize) {
    const normalized = {};
    Object.keys(value).forEach(key => { normalized[key] = value[key]; });
    normalized.props = {};
    Object.keys(value.props).forEach(key => { normalized.props[key] = value.props[key]; });
    normalized.props.testID = '<string>';
    Object.defineProperty(normalized, '__normalizedTestID', { value: true });
    return serialize(normalized);
  },
};
`);
JS
npm test -- --config=/tmp/rebench-jest-config.json --verbose --no-color --maxWorkers=1
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
