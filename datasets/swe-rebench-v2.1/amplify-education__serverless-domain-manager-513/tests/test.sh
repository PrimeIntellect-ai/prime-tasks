#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/serverless-domain-manager
TEST_FILES=(test/integration-tests/basic.test.ts test/integration-tests/basic/apigateway-with-export/handler.js test/integration-tests/basic/apigateway-with-export/serverless.yml test/integration-tests/basic/apigateway-with-import/handler.js test/integration-tests/basic/apigateway-with-import/serverless.yml test/integration-tests/basic/basepath-mapping/handler.js test/integration-tests/basic/basepath-mapping/serverless.yml test/integration-tests/basic/create-domain-idempotent/handler.js test/integration-tests/basic/create-domain-idempotent/serverless.yml test/integration-tests/basic/deploy-idempotent/handler.js test/integration-tests/basic/deploy-idempotent/serverless.yml test/integration-tests/basic/http-api-multiple/handler.js test/integration-tests/basic/http-api-multiple/serverless.yml test/integration-tests/basic/mutual-tls/handler.js test/integration-tests/basic/mutual-tls/serverless.yml test/integration-tests/basic/null-basepath-mapping/handler.js test/integration-tests/basic/null-basepath-mapping/serverless.yml test/integration-tests/basic/route53-profile/handler.js test/integration-tests/basic/route53-profile/serverless.yml test/integration-tests/deploy/auto-domain/handler.js test/integration-tests/deploy/auto-domain/serverless.yml test/integration-tests/deploy/basepath-nested-stack/handler.js test/integration-tests/deploy/basepath-nested-stack/serverless.yml test/integration-tests/deploy/basepath/handler.js test/integration-tests/deploy/basepath/serverless.yml test/integration-tests/deploy/custom-apigateway/handler.js test/integration-tests/deploy/custom-apigateway/serverless.yml test/integration-tests/deploy/default/handler.js test/integration-tests/deploy/default/serverless.yml test/integration-tests/deploy/http-api/handler.js test/integration-tests/deploy/http-api/serverless.yml test/integration-tests/deploy/regional-basepath/handler.js test/integration-tests/deploy/regional-basepath/serverless.yml test/integration-tests/deploy/regional-stage-basepath/handler.js test/integration-tests/deploy/regional-stage-basepath/serverless.yml test/integration-tests/deploy/regional-tls-1-0/handler.js test/integration-tests/deploy/regional-tls-1-0/serverless.yml test/integration-tests/deploy/route-53-latency-routing/handler.js test/integration-tests/deploy/route-53-latency-routing/serverless.yml test/integration-tests/deploy/route-53-weighted-routing/handler.js test/integration-tests/deploy/route-53-weighted-routing/serverless.yml test/integration-tests/deploy/stage-basepath/handler.js test/integration-tests/deploy/stage-basepath/serverless.yml test/integration-tests/deploy/web-socket/handler.js test/integration-tests/deploy/web-socket/serverless.yml test/unit-tests/index.test.ts)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
find ./test/unit-tests -name '*.test.ts' | xargs npx mocha -r ts-node/register --project tsconfig.json --timeout 5000 --reporter spec
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
