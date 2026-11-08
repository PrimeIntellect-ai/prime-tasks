#!/bin/bash
set -uo pipefail

WORKDIR=/tailwindcss
TEST_FILES=(tests/jit/basic-usage.test.css tests/jit/relative-purge-paths.test.css)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
npx cross-env TAILWIND_MODE=build jest --verbose --no-colors; jest_status=$?; node -e "require('@babel/register')({presets:['@babel/preset-env']}); const assert=require('assert'); const postcss=require('postcss'); const tailwind=require('./src/jit/index.js').default; const css='@tailwind base; @tailwind utilities; .scn-2-applied-translation { @apply -translate-x-3.5 translate-y-3.5; }'; postcss(tailwind({mode:'jit',corePlugins:{preflight:false},theme:{},plugins:[]})).process(css,{from:process.cwd()+'/tests/jit/apply.test.js'}).then(result=>{const declarations=[]; result.root.walkDecls(decl=>declarations.push(decl)); assert(declarations.some(decl=>decl.prop==='--tw-translate-x' && decl.value==='-0.875rem')); assert(declarations.some(decl=>decl.prop==='--tw-translate-y' && decl.value==='0.875rem')); assert(declarations.some(decl=>decl.prop==='transform' && decl.value==='var(--tw-transform)')); assert(declarations.some(decl=>decl.prop==='--tw-transform'));}).catch(error=>{console.error(error); process.exitCode=1});"; probe_status=$?; test "$jest_status" -eq 0 && test "$probe_status" -eq 0
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
