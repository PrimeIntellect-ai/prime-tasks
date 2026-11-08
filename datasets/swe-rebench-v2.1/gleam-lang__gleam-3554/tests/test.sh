#!/bin/bash
set -uo pipefail

WORKDIR=/gleam
TEST_FILES=(test-package-compiler/src/snapshots/test_package_compiler__generated_tests__import_shadowed_name_warning.snap)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
export RUST_TEST_THREADS=1
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
test_status=0
if cargo test --workspace --verbose -- --nocapture; then :; else test_status=1; fi
if cargo build -q -p gleam; then :; else test_status=1; fi
repo=$PWD
tmp=$(mktemp -d)
printf 'name = "sample"\nversion = "1.0.0"\ndescription = "sample"\nlicenses = []\n' > "$tmp/gleam.toml"
mkdir -p "$tmp/src"
printf 'pub fn main() {\n  1 + True\n}\n\nfn unused() { Nil }\n' > "$tmp/src/main.gleam"
if (cd "$tmp" && "$repo/target/debug/gleam" check) > "$tmp/diagnostics.txt" 2>&1; then cli_status=0; else cli_status=$?; fi
if [ "$cli_status" -eq 0 ]; then test_status=1; fi
if python3 - "$tmp/diagnostics.txt" <<'PYTHON'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
warning_position = text.find("warning: ")
error_position = text.find("error: ")
if warning_position < 0 or error_position < 0 or warning_position >= error_position:
    raise AssertionError("the project did not report a warning before its error")
if not text[:error_position].endswith("\n\n"):
    raise AssertionError("the final warning and first error need an empty line between them")
PYTHON
then
  printf 'Mixed warning/error diagnostics are separated by an empty line.\n'
else
  test_status=1
fi
rm -rf "$tmp"
[ "$test_status" -eq 0 ]
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
