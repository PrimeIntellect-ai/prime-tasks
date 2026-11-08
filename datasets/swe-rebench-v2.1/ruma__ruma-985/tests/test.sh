#!/bin/bash
set -uo pipefail
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

WORKDIR=/ruma
TEST_FILES=(crates/ruma-common/tests/events/mod.rs crates/ruma-common/tests/events/relations.rs)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
export RUST_TEST_THREADS=1
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
export PATH=/root/.cargo/bin:/usr/local/cargo/bin:$PATH && cargo test --tests --features __ci -- --nocapture --skip ui && {
cargo build -p ruma-client-api --features 'unstable-msc3440,server' &&
client_api=$(find target/debug/deps -maxdepth 1 -name 'libruma_client_api-*.rlib' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-) &&
common=$(find target/debug/deps -maxdepth 1 -name 'libruma_common-*.rlib' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-) &&
rm -f /tmp/rebench-filter-tests &&
for jsonlib in target/debug/deps/libserde_json-*.rlib; do
    if rustc --edition=2018 --test -L dependency=target/debug/deps --extern ruma_client_api="$client_api" --extern ruma_common="$common" --extern serde_json="$jsonlib" -o /tmp/rebench-filter-tests - 2>/tmp/rebench-filter-rustc.log <<'RS'
use ruma_client_api::filter::IncomingRoomEventFilter;
use serde_json::{json, to_value};

#[test]
fn relation_types_round_trip_and_nonempty() {
    let expected = json!({"io.element.relation_types": ["io.element.thread"]});
    let incoming: IncomingRoomEventFilter = serde_json::from_value(expected.clone()).unwrap();
    let incoming_json = to_value(&incoming).unwrap();
    assert_eq!(incoming_json.get("io.element.relation_types"), expected.get("io.element.relation_types"));
    assert!(!incoming.is_empty());
}

#[test]
fn relation_senders_round_trip_and_nonempty() {
    let expected = json!({"io.element.relation_senders": ["@alice:example.org"]});
    let incoming: IncomingRoomEventFilter = serde_json::from_value(expected.clone()).unwrap();
    let incoming_json = to_value(&incoming).unwrap();
    assert_eq!(incoming_json.get("io.element.relation_senders"), expected.get("io.element.relation_senders"));
    assert!(!incoming.is_empty());
}
RS
    then break; fi
done &&
if test -x /tmp/rebench-filter-tests; then /tmp/rebench-filter-tests; else cat /tmp/rebench-filter-rustc.log; false; fi
}
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
