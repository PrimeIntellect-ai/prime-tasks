#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/kurtosis
TEST_FILES=(container-engine-lib/lib/backend_interface/objects/service/service_config_test.go container-engine-lib/lib/database_accessors/enclave_db/service_registration/repository_test.go core/server/api_container/server/service_network/default_service_network_test.go core/server/api_container/server/startosis_engine/kurtosis_instruction/add_service/add_service_shared_test.go core/server/api_container/server/startosis_engine/kurtosis_starlark_framework/test_engine/add_service_framework_test.go core/server/api_container/server/startosis_engine/kurtosis_starlark_framework/test_engine/add_services_framework_test.go core/server/api_container/server/startosis_engine/kurtosis_starlark_framework/test_engine/service_config_image_build_spec_test.go core/server/api_container/server/startosis_engine/kurtosis_starlark_framework/test_engine/service_config_image_registry_spec_test.go core/server/api_container/server/startosis_engine/kurtosis_starlark_framework/test_engine/service_config_minimal_framework_test.go core/server/api_container/server/startosis_engine/kurtosis_starlark_framework/test_engine/service_config_toleration_test.go core/server/api_container/server/startosis_engine/kurtosis_starlark_framework/test_engine/static_constants.go internal_testsuites/starlark/taints_and_tolerations/taints_and_toleration_test.star)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
cd /kurtosis && /usr/local/go/bin/go test -v ./container-engine-lib/lib/backend_interface/objects/service/... ./core/server/api_container/server/startosis_engine/kurtosis_starlark_framework/test_engine/... ./core/server/api_container/server/startosis_engine/kurtosis_instruction/add_service/...
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
