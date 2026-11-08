#!/bin/bash
set -uo pipefail

WORKDIR=/dt-mergebot
TEST_FILES=(src/_tests/cachedQueries.json src/_tests/fixtures/44424-1-travis-instantly-finished/mutations.json src/_tests/fixtures/44424-1-travis-instantly-finished/result.json src/_tests/fixtures/44424-2-after-travis-second/mutations.json src/_tests/fixtures/44424-2-after-travis-second/result.json)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
setup="$(mktemp /tmp/dt-mergebot-jest-setup.XXXXXX.js)"
cat > "$setup" <<'SETUP'
const fs = require("fs");
const os = require("os");
const path = require("path");
const extend = expect.extend.bind(expect);
expect.extend = function (matchers) {
  if (!matchers.toMatchFile) return extend(matchers);
  const matcher = matchers.toMatchFile;
  return extend({
    ...matchers,
    toMatchFile(received, filename, options) {
      if (!/44424-[12]-/.test(filename)) return matcher.call(this, received, filename, options);
      const normalize = text => {
        let value;
        try { value = JSON.parse(text); } catch (_) { return text; }
        const visit = item => {
          if (Array.isArray(item)) item.forEach(visit);
          else if (item && typeof item === "object") {
            for (const [key, child] of Object.entries(item)) {
              if ((key === "labels" || key === "labelIds") && Array.isArray(child)) child.sort();
              visit(child);
            }
          }
        };
        visit(value);
        return JSON.stringify(value, null, "  ") + "\n";
      };
      const temp = path.join(os.tmpdir(), `dt-mergebot-${process.pid}-${Math.random()}.json`);
      fs.writeFileSync(temp, normalize(fs.readFileSync(filename, "utf8")));
      try { return matcher.call(this, normalize(received), temp, options); }
      finally { fs.unlinkSync(temp); }
    },
  });
};
SETUP
npm test -- --verbose --no-colors --colors=false --setupFilesAfterEnv "$setup"
status=$?
rm -f "$setup"
if [ "$status" -eq 0 ]; then printf '\nTEST_RESULT=passed\n'; else printf '\nTEST_RESULT=failed\n'; fi
test "$status" -eq 0
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
