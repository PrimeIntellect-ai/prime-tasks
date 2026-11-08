#!/bin/bash
set -uo pipefail

WORKDIR=/swc
TEST_FILES=(crates/swc_ecma_parser/tests/test262-error-references/fail/1aefe47e20eb91fa.module.js.stderr)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
export RUST_TEST_THREADS=1
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
export PATH="/root/.cargo/bin:$PATH" && cargo test --workspace --exclude swc_ecma_transforms_compat --lib --bins --no-fail-fast -- --nocapture --show-output && python3 - <<'PYCODE'
from pathlib import Path
import glob
import subprocess

# Inspect actual parser diagnostics while allowing additional diagnostic blocks.
fixture = Path("crates/swc_ecma_parser/tests/test262-error-references/fail/1aefe47e20eb91fa.module.js.stderr")
original = fixture.read_bytes()
try:
    fixture.write_bytes(b"")
    parser = subprocess.run(
        ["cargo", "test", "-p", "swc_ecma_parser", "--features", "verify", "--test", "test262", "error", "--", "--exact", "test262::error_reporting::fail::1aefe47e20eb91fa.module.js", "--nocapture"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
finally:
    fixture.write_bytes(original)
output = parser.stdout
first = output.find("top level await requires target to es2017 or higher and topLevelAwait:true for ecmascript")
second = output.find("`await` cannot be used as an identifier in an async context")
swc_lib = next(iter(glob.glob("target/debug/deps/libswc-*.rlib")), None)
common_lib = next(iter(glob.glob("target/debug/deps/libswc_common-*.rlib")), None)
if not swc_lib or not common_lib:
    raise RuntimeError("compiled SWC libraries were not found")
program = r'''use std::sync::Arc;
use swc::{config::{Config, IsModule, Options}, try_with_handler, Compiler, HandlerOpts};
use swc_common::{FileName, Globals, SourceMap, GLOBALS};
fn main() {
    GLOBALS.set(&Globals::new(), || {
        let cm = Arc::<SourceMap>::default();
        let compiler = Compiler::new(cm.clone());
        let result = try_with_handler(cm.clone(), HandlerOpts { ..Default::default() }, |handler| {
            let file = cm.new_source_file(FileName::Real("input.js".into()), r#"try { await; } catch { console.log("caught"); }"#.into());
            compiler.process_js_file(file, handler, &Options { config: Config { is_module: IsModule::Bool(false), ..Default::default() }, ..Default::default() })
        });
        let output = result.expect("the reported script should transpile successfully");
        assert!(!output.code.trim().is_empty());
        assert!(output.code.contains("caught"));
    });
}'''
compiled = subprocess.run(
    ["rustc", "--edition=2021", "-L", "dependency=target/debug/deps", "--extern", f"swc={swc_lib}", "--extern", f"swc_common={common_lib}", "-o", "/tmp/rebench-await-transpile", "-"],
    input=program,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)
if compiled.returncode != 0:
    print(compiled.stdout)
    raise RuntimeError("failed to compile the behavioral transpilation probe")
run = subprocess.run(["/tmp/rebench-await-transpile"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
if run.returncode != 0:
    print(run.stdout)
    raise RuntimeError("SWC failed to transpile the reported script")
if parser.returncode == 0 or first < 0 or second < 0 or first >= second:
    print(output)
    raise RuntimeError("required module diagnostics were not observed in order")
print("Transpilation and ordered diagnostic behavior passed")
PYCODE
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
