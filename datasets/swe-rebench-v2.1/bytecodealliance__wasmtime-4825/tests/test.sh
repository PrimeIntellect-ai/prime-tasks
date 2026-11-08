#!/bin/bash
set -uo pipefail

WORKDIR=/wasmtime
TEST_FILES=(tests/misc_testsuite/component-model/types.wast)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
export RUST_TEST_THREADS=1
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
cargo test --test all -- --nocapture --test-threads 1
suite_status=$?
cargo build --manifest-path crates/misc/component-fuzz-util/Cargo.toml && FUZZ_UTIL=$(find target/debug/deps -maxdepth 1 -name 'libcomponent_fuzz_util-*.rlib' | head -1) && ARBITRARY=$(find target/debug/deps -maxdepth 1 -name 'libarbitrary-*.rlib' | head -1) && rustc --edition=2021 --test -L dependency=target/debug/deps --extern component_fuzz_util="$FUZZ_UTIL" --extern arbitrary="$ARBITRARY" -o /tmp/rebench-arbitrary-depth-test - <<'RS'
use arbitrary::{Arbitrary, Unstructured};
use component_fuzz_util::Type;

fn nesting(ty: &Type) -> usize {
    match ty {
        Type::List(inner) | Type::Option(inner) => 1 + nesting(inner),
        Type::Record(items) => 1 + items.iter().map(nesting).max().unwrap_or(0),
        Type::Tuple(items) => 1 + items.iter().map(nesting).max().unwrap_or(0),
        Type::Union(items) => 1 + items.iter().map(nesting).max().unwrap_or(0),
        Type::Variant(items) => 1 + items.iter().filter_map(Option::as_ref).map(nesting).max().unwrap_or(0),
        Type::Result { ok, err } => 1 + ok.iter().chain(err.iter()).map(|ty| nesting(ty)).max().unwrap_or(0),
        _ => 0,
    }
}

#[test]
fn arbitrary_types_have_bounded_nesting() {
    let mut inputs = Vec::new();
    for byte in 0..=u8::MAX {
        let mut bytes = vec![byte; 256];
        bytes.push(0);
        inputs.push(bytes);
    }
    let mut derived_enum_path = vec![0x99; 1024];
    derived_enum_path.extend([0; 4]);
    inputs.push(derived_enum_path);

    let mut generated_types = 0;
    let mut maximum_depth = 0;
    for bytes in inputs {
        let mut input = Unstructured::new(&bytes);
        if let Ok(ty) = Type::arbitrary(&mut input) {
            generated_types += 1;
            maximum_depth = maximum_depth.max(nesting(&ty));
        }
    }
    assert!(generated_types > 0, "the supplied arbitrary inputs generate no types");
    assert!(maximum_depth < 256, "generated nesting reached 256 constructors");
}
RS
arbitrary_status=$?
if [ "$arbitrary_status" -eq 0 ]; then
  /tmp/rebench-arbitrary-depth-test --nocapture
  arbitrary_status=$?
fi
test "$suite_status" -eq 0 -a "$arbitrary_status" -eq 0
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
