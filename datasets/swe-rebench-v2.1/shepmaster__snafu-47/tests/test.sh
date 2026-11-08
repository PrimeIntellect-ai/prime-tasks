#!/bin/bash
set -uo pipefail

WORKDIR=/snafu
TEST_FILES=(compatibility-tests/compile-fail/tests/compile-fail/error-reporting.rs compatibility-tests/v1_18/tests/v1_18.rs compatibility-tests/v1_30/tests/v1_30.rs compatibility-tests/v1_34/tests/clean_attributes.rs compatibility-tests/without-backtrace/tests/without_backtrace.rs tests/opaque.rs)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
export PATH=/root/.cargo/bin:/usr/local/cargo/bin:$PATH && cargo test --verbose && \
snafu_lib=$(find target/debug/deps -maxdepth 1 -name 'libsnafu-*.rlib' | head -n 1) && \
check_shape() { \
    shape="$1"; definition="$2"; expected="$3"; \
    source="/tmp/rebench-shape-${shape}.rs"; output="/tmp/rebench-shape-${shape}.log"; \
    printf '%s\n' '#[derive(snafu::Snafu)]' "$definition" > "$source"; \
    if rustc --edition=2018 --crate-type lib "$source" -L dependency=target/debug/deps --extern "snafu=$snafu_lib" --error-format short -o "/tmp/rebench-shape-${shape}.rlib" > "$output" 2>&1; then \
        printf 'invalid %s unexpectedly compiled\n' "$shape"; return 1; \
    else \
        if grep -F "$expected" "$output" > /dev/null; then printf '%s diagnostic verified\n' "$shape"; else cat "$output"; return 1; fi; \
    fi; \
} && \
check_shape union 'union Bad { field: i32 }' 'Can only derive `Snafu` for an enum or a newtype' && \
check_shape unit 'struct Bad;' 'tuple structs' && \
check_shape named 'struct Bad { field: i32 }' 'tuple structs' && \
check_shape zero 'struct Bad();' 'exactly one field' && \
check_shape multiple 'struct Bad(i32, i32);' 'exactly one field'
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
