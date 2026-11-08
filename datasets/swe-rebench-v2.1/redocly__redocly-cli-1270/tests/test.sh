#!/bin/bash
set -uo pipefail

WORKDIR=/redocly-cli
TEST_FILES=(__tests__/build-docs/build-docs-with-config-option/nested/openapi.yaml __tests__/bundle/bundle-lint-format/openapi.yaml __tests__/bundle/primitive-types/openapi.yaml __tests__/bundle/primitive-types/snapshot.js __tests__/commands.test.ts __tests__/join/decorate/bar.yaml __tests__/join/decorate/foo.yaml __tests__/join/decorate/snapshot.js __tests__/join/ignore-decorators/bar.yaml __tests__/join/ignore-decorators/foo.yaml __tests__/join/ignore-decorators/snapshot.js __tests__/join/references-in-parameters/bar.yaml __tests__/join/references-in-parameters/foo.yaml __tests__/join/references-in-parameters/snapshot.js __tests__/join/with-metadata/pet.yaml __tests__/join/with-metadata/snapshot.js __tests__/join/with-metadata/test.yaml __tests__/lint/assertions-camel-case-twice/openapi.yaml __tests__/lint/assertions-error/openapi.yaml __tests__/lint/assertions-error/snapshot.js __tests__/lint/assertions/openapi.yaml __tests__/lint/no-server-variables-empty-enum-errror/openapi.yaml __tests__/lint/no-server-variables-empty-enum-errror/snapshot.js __tests__/lint/no-server-variables-empty-enum/openapi.yaml __tests__/lint/oas3.1-error/openapi.yaml __tests__/lint/oas3.1/openapi.yaml __tests__/miscellaneous/resolve-refs-in-preprocessors/openapi.yaml __tests__/miscellaneous/resolve-refs-in-preprocessors/snapshot.js __tests__/smoke/openapi.yaml packages/core/src/__tests__/lint.test.ts packages/core/src/rules/oas3/__tests__/no-server-example.com.test.ts packages/core/src/rules/oas3/__tests__/spec/spec.test.ts)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
npm run unit -- --verbose --no-color --maxWorkers=1
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
