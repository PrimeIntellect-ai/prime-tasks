#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/bitflags
TEST_FILES=(tests/compile-pass/doc_alias.rs)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
export RUST_TEST_THREADS=1
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
cargo test -- --nocapture --quiet && rm -rf /tmp/bitflags-doc-alias && rustdoc tests/compile-pass/doc_alias.rs --crate-name doc_alias --edition=2018 --crate-type lib -L dependency=target/debug/deps --extern bitflags="$(ls -t target/debug/deps/libbitflags-*.rlib | head -n 1)" --out-dir /tmp/bitflags-doc-alias && { grep -R -q 'TYPE_ALIAS' /tmp/bitflags-doc-alias/search.index/name || { echo 'missing type documentation alias'; false; }; } && { grep -R -q 'FLAG_ALIAS' /tmp/bitflags-doc-alias/search.index/name || { echo 'missing flag documentation alias'; false; }; } && RUSTC_BOOTSTRAP=1 rustdoc -Z unstable-options --output-format json tests/compile-pass/doc_alias.rs --crate-name doc_alias --edition=2018 --crate-type lib -L dependency=target/debug/deps --extern bitflags="$(ls -t target/debug/deps/libbitflags-*.rlib | head -n 1)" -o /tmp/bitflags-doc-alias-json && python3 -c 'import json; d=json.load(open("/tmp/bitflags-doc-alias-json/doc_alias.json")); items=d["index"].values(); type_alias=chr(35)+"[doc(alias = "+chr(34)+"TYPE_ALIAS"+chr(34)+")]"; flag_alias=chr(35)+"[doc(alias = "+chr(34)+"FLAG_ALIAS"+chr(34)+")]"; assert any(i.get("name")=="Flags" and any(a.get("other")==type_alias for a in i.get("attrs", [])) for i in items), "TYPE_ALIAS is not attached to Flags"; assert any(i.get("name")=="A" and any(a.get("other")==flag_alias for a in i.get("attrs", [])) for i in items), "FLAG_ALIAS is not attached to flag A"'
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
