#!/bin/bash
set -uo pipefail

WORKDIR=/clickhouse-sql-parser
TEST_FILES=(parser/testdata/query/format/select_column_alias_string.sql parser/testdata/query/output/select_column_alias_string.sql.golden.json parser/testdata/query/select_column_alias_string.sql)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
other_tests="$(go test ./parser -list '^Test' | grep '^Test' | grep -v '^TestParser_ParseStatements$' | paste -sd '|')"
parse_cases="$(find parser/testdata/dml parser/testdata/ddl parser/testdata/query parser/testdata/basic -maxdepth 1 -type f -name '*.sql' ! -name 'select_column_alias_string.sql' -printf '%f\n' | paste -sd '|')"
if go test -v ./... -covermode=atomic -coverprofile=coverage.out -race -compatible -run "^(${other_tests}|TestParser_ParseStatements/(${parse_cases}))"; then full_status=0; else full_status=1; fi
source_backup="$(mktemp)"
golden_backup="$(mktemp)"
cp parser/testdata/query/select_column_alias_string.sql "$source_backup"
cp parser/testdata/query/output/select_column_alias_string.sql.golden.json "$golden_backup"
printf 'SELECT service$$name FROM test_table\n' > parser/testdata/query/select_column_alias_string.sql
if go test ./parser -run '^TestParser_ParseStatements/select_column_alias_string.sql$' -update; then parse_status=0; else parse_status=1; fi
cp "$source_backup" parser/testdata/query/select_column_alias_string.sql
cp "$golden_backup" parser/testdata/query/output/select_column_alias_string.sql.golden.json
rm "$source_backup" "$golden_backup"
test "$full_status" -eq 0 && test "$parse_status" -eq 0
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
