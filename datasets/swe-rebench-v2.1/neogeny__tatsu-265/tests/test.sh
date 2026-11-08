#!/bin/bash
set -uo pipefail

WORKDIR=/TatSu
TEST_FILES=(test/__init__.py test/__main__.py test/ast_test.py test/buffering_test.py test/codegen_test.py test/diagram_test.py test/grammar/directive_test.py test/grammar/firstfollow_test.py test/grammar/join_test.py test/grammar/keyword_test.py test/grammar/left_recursion_test.py test/grammar/lookahead_test.py test/grammar/parameter_test.py test/grammar/pattern_test.py test/grammar/pretty_test.py test/grammar/semantics_test.py test/grammar/stateful_test.py test/grammar/syntax_test.py test/model_test.py test/parser_equivalence_test.py test/parsing_test.py test/walker_test.py)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
pytest --no-header -rA --tb=line --color=no -p no:cacheprovider -W ignore::DeprecationWarning test/__init__.py test/__main__.py test/ast_test.py test/buffering_test.py test/codegen_test.py test/diagram_test.py test/grammar/directive_test.py test/grammar/firstfollow_test.py test/grammar/join_test.py test/grammar/keyword_test.py test/grammar/left_recursion_test.py test/grammar/lookahead_test.py test/grammar/parameter_test.py test/grammar/pattern_test.py test/grammar/pretty_test.py test/grammar/semantics_test.py test/grammar/stateful_test.py test/grammar/syntax_test.py test/model_test.py test/parser_equivalence_test.py test/parsing_test.py test/walker_test.py
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
