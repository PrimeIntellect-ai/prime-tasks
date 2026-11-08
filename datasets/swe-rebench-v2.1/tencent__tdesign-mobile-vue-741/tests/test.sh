#!/bin/bash
set -uo pipefail

WORKDIR=/tdesign-mobile-vue
TEST_FILES=(src/progress/__test__/__snapshots__/demo.test.jsx.snap src/progress/__test__/index.test.jsx)
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
npm run test:unit -- src/progress --reporter=verbose --coverage --threads false && node -e 'const c=require("./test/unit/coverage/coverage-final.json");let S=0,Sc=0,B=0,Bc=0,F=0,Fc=0;const lm={};for(const [path,f] of Object.entries(c).filter(([path])=>path.includes("/src/progress/"))){for(const k in f.s){S++;if(f.s[k]>0)Sc++;}for(const k in f.b){const a=f.b[k];B+=a.length;Bc+=a.filter(x=>x>0).length;}for(const k in f.f){F++;if(f.f[k]>0)Fc++;}for(const k in f.statementMap){const l=f.statementMap[k].start.line;if(lm[l]===undefined)lm[l]=false;if(f.s[k]>0)lm[l]=true;}}const L=Object.keys(lm).length,Lc=Object.values(lm).filter(Boolean).length;const p=(a,b)=>a/b*100;const r={statements:p(Sc,S),branches:p(Bc,B),functions:p(Fc,F),lines:p(Lc,L)};console.log("coverage",JSON.stringify(r));if(r.statements<80||r.branches<80||r.lines<80){console.error("coverage below 80%");process.exit(1);}'
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
