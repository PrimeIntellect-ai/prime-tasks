#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/ember-cli
TEST_FILES=(tests/fixtures/addon/defaults/package.json tests/fixtures/addon/pnpm/package.json tests/fixtures/addon/typescript/package.json tests/fixtures/addon/yarn/package.json tests/fixtures/app/defaults/package.json tests/fixtures/app/embroider-no-welcome/package.json tests/fixtures/app/embroider-pnpm/package.json tests/fixtures/app/embroider-yarn/package.json tests/fixtures/app/embroider/package.json tests/fixtures/app/npm/package.json tests/fixtures/app/pnpm/package.json tests/fixtures/app/typescript-embroider/package.json tests/fixtures/app/typescript/package.json tests/fixtures/app/yarn/package.json)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
node --unhandled-rejections=strict -e '
const fs = require("fs");
const semver = require("semver");
const originalReadFileSync = fs.readFileSync;
fs.readFileSync = function (path, options) {
  const contents = originalReadFileSync.apply(this, arguments);
  const fixturePackage = typeof path === "string" && path.includes("/tests/fixtures/") && path.endsWith("/package.json");
  const comparisonRead = (new Error().stack || "").includes("chai-files");
  if (typeof contents !== "string" || (!fixturePackage && !comparisonRead)) {
    return contents;
  }
  return contents.replace(/("ember-resolver"\s*:\s*")([^"]+)(")/, (match, before, versionRange, after) => {
    const range = semver.validRange(versionRange);
    const includesMajor13 = range && semver.intersects(range, ">=13.0.0 <14.0.0");
    const excludesOtherMajors = range && !semver.intersects(range, "<13.0.0") && !semver.intersects(range, ">=14.0.0");
    return includesMajor13 && excludesOtherMajors ? `${before}<ember-resolver-v13>${after}` : match;
  });
};
process.argv = [process.argv[0], "tests/runner", ...(process.env.REBENCH_MOCHA_ARGS || "").split(" ").filter(Boolean)];
require("./tests/runner");
'
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
