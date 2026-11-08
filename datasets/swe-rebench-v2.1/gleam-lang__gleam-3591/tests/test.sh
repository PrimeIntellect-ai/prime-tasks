#!/bin/bash
set -uo pipefail

WORKDIR=/gleam
TEST_FILES=(compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__errors__type_imported_as_value.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__import_type_duplicate.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__unqualified_import_errors_do_not_block_later_unqualified.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__unqualified_using_opaque_constructo.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__unqualified_using_private_constructo.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__unqualified_using_private_constructor_pattern.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__unqualified_using_private_function.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_opaque_constructo.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_constructo.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_constructor_pattern.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_custom_type.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_external_type.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_function.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_type_alias.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_unqualified_custom_type.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_unqualified_external_type.snap compiler-core/src/type_/tests/snapshots/gleam_core__type___tests__imports__using_private_unqualified_type_alias.snap test-package-compiler/src/snapshots/test_package_compiler__generated_tests__opaque_type_destructure.snap test-package-compiler/src/snapshots/test_package_compiler__generated_tests__unknown_module_field_in_constant.snap test-package-compiler/src/snapshots/test_package_compiler__generated_tests__unknown_module_field_in_expression.snap test-package-compiler/src/snapshots/test_package_compiler__generated_tests__unknown_module_field_in_import.snap)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
export RUST_TEST_THREADS=1
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
cargo test --workspace --verbose -- --nocapture
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
