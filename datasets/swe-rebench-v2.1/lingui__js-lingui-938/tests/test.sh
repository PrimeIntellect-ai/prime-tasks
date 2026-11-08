#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/js-lingui
TEST_FILES=(packages/conf/src/__snapshots__/index.test.ts.snap)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
yarn test --maxWorkers=1 --no-cache --verbose --silent=false
tests_status=$?
node <<'NODE'
const assert = require('assert')
const fs = require('fs')
const path = require('path')
const os = require('os')
const ts = require('typescript')
const Module = require('module')
const sourcePath = path.resolve('packages/conf/src/index.ts')
const js = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2019,
    esModuleInterop: true,
  },
}).outputText
const conf = new Module(sourcePath, module)
conf.filename = sourcePath
conf.paths = Module._nodeModulePaths(path.dirname(sourcePath))
conf._compile(js, sourcePath)
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'lingui-contract-'))
const configPath = path.join(directory, '.linguirc')
fs.writeFileSync(
  configPath,
  JSON.stringify({ locales: ['en'], compilerBabelOptions: { minified: false } })
)
const warnings = []
const originalWarn = console.warn
try {
  console.warn = (...args) => warnings.push(args.join(' '))
  conf.exports.getConfig({ configPath })
  assert.deepStrictEqual(
    warnings,
    [],
    `valid compilerBabelOptions produced a validation warning: ${warnings.join('; ')}`
  )
} finally {
  console.warn = originalWarn
  fs.rmSync(directory, { recursive: true, force: true })
}
const config = conf.exports.getConfig({ skipValidation: true })
assert.deepStrictEqual(config.compilerBabelOptions, {
  minified: true,
  jsescOption: { minimal: true },
})
console.log('compilerBabelOptions contract checks passed')
NODE
behavior_status=$?
if [ "$tests_status" -ne 0 ] || [ "$behavior_status" -ne 0 ]; then false; else true; fi
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
