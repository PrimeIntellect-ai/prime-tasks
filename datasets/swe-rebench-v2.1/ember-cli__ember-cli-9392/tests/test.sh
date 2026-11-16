#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/ember-cli
TEST_FILES=(tests/fixtures/addon/.eslintrc.js tests/fixtures/addon/defaults/package.json tests/fixtures/addon/yarn/package.json tests/fixtures/app/.eslintrc.js tests/fixtures/app/defaults/package.json tests/fixtures/app/embroider-no-welcome/package.json tests/fixtures/app/embroider/package.json tests/fixtures/app/npm/package.json tests/fixtures/app/yarn/package.json)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
node --unhandled-rejections=strict -e 'const captureExit = require("capture-exit"); captureExit.captureExit(); const glob = require("glob"); const Mocha = require("mocha"); const fs = require("fs-extra"); const path = require("path"); const assert = require("assert"); const tmp = require("ember-cli-internal-test-helpers/lib/helpers/tmp"); const ember = require("./tests/helpers/ember"); const root = process.cwd(); fs.removeSync(".deps-tmp"); const mocha = new Mocha({ timeout: 5000, retries: 2 }); mocha.suite.emit("pre-require", global, "inline", mocha); mocha.grep(/(?:app defaults|addon defaults|app \+ npm \+ !welcome|app \+ yarn \+ welcome|addon \+ yarn \+ welcome)$/).invert(); for (const f of glob.sync("tests/{unit,integration,acceptance}/**/*-test.js")) mocha.addFile(f); const chai = require("./tests/chai"); mocha.suite.afterEach(() => chai.expect(process.cwd()).to.equal(root)); describe("QUnit blueprint behavior", function () { this.timeout(20000); const dir = "./tmp/rebench-qunit"; beforeEach(async function () { await tmp.setup(dir); process.chdir(dir); }); afterEach(async function () { process.chdir(root); await tmp.teardown(dir); }); for (const [kind, args] of [["app", ["new", "foo", "--skip-npm", "--skip-bower", "--skip-git"]], ["addon", ["addon", "foo", "--skip-npm", "--skip-bower", "--skip-git"]]]) { it("generates " + kind + " dependencies and enables QUnit linting for test files", async function () { await ember(args); const pkg = fs.readJsonSync("package.json"); const pluginRange = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"].map((section) => pkg[section] && pkg[section]["eslint-plugin-qunit"]).find((value) => typeof value === "string"); assert(pluginRange && pluginRange.length > 0); const lintConfig = require(path.join(process.cwd(), ".eslintrc.js")); const minimatch = require("minimatch"); const enabled = (config) => [].concat(config.extends || []).some((value) => String(value).includes("qunit")) || Object.keys(config.rules || {}).some((name) => name.startsWith("qunit/")); const globalSettings = enabled(lintConfig); const testSettings = (lintConfig.overrides || []).some((override) => [].concat(override.files || []).some((pattern) => minimatch("tests/example-test.js", pattern)) && enabled(override)); assert(globalSettings || testSettings); }); } }); console.time("Mocha Tests Running Time"); mocha.run((failures) => { console.timeEnd("Mocha Tests Running Time"); process.exitCode = failures; });'
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
