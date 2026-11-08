#!/bin/bash
set -uo pipefail

WORKDIR=/memefish
TEST_FILES=(testdata/input/expr/array_literal_empty_with_types.sql testdata/input/expr/array_literal_empty_without_array_keyword.sql testdata/input/expr/array_literal_empty_without_types.sql testdata/result/dml/insert_select.sql.txt testdata/result/expr/array_literal_empty_with_types.sql.txt testdata/result/expr/array_literal_empty_without_array_keyword.sql.txt testdata/result/expr/array_literal_empty_without_types.sql.txt testdata/result/query/select_cast.sql.txt testdata/result/query/select_expr.sql.txt testdata/result/query/select_literals_all.sql.txt testdata/result/query/select_literals_array.sql.txt testdata/result/query/select_literals_array_invalid.sql.txt testdata/result/query/select_unnest_with_offset.sql.txt testdata/result/query/select_unnest_with_offset_and_alias.sql.txt testdata/result/query/select_unnest_with_offset_and_alias_min.sql.txt testdata/result/statement/insert_select.sql.txt testdata/result/statement/select_cast.sql.txt testdata/result/statement/select_expr.sql.txt testdata/result/statement/select_literals_all.sql.txt testdata/result/statement/select_literals_array.sql.txt testdata/result/statement/select_literals_array_invalid.sql.txt testdata/result/statement/select_unnest_with_offset.sql.txt testdata/result/statement/select_unnest_with_offset_and_alias.sql.txt testdata/result/statement/select_unnest_with_offset_and_alias_min.sql.txt)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
go test -v ./...
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
