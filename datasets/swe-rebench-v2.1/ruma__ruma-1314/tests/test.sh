#!/bin/bash
set -uo pipefail

WORKDIR=/ruma
TEST_FILES=(crates/ruma-common/tests/events/relations.rs crates/ruma-common/tests/events/room_message.rs)
export CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS=fallback
IFS= read -r -d '' HARBOR_TEST_CMD <<'HARBOR_TEST_CMD_EOF'
export PATH=/root/.cargo/bin:/usr/local/cargo/bin:$PATH && cargo test --tests --features __ci -- events::relations::thread events::room_message::reply && check_feature_absent() { package="$1"; if cargo check -p "$package" --features unstable-msc3440 > /tmp/rebench-obsolete-feature.log 2>&1; then echo "$package still exposes unstable-msc3440"; return 1; else grep -q "does not contain this feature: unstable-msc3440" /tmp/rebench-obsolete-feature.log; fi; } && check_feature_absent ruma-common && check_feature_absent ruma && check_feature_absent ruma-client-api && {
  set -e
  PROBE_DIR=$(mktemp -d /tmp/ruma-filter-probe.XXXXXX)
  mkdir -p "$PROBE_DIR/src"
  cat >"$PROBE_DIR/Cargo.toml" <<EOF
[package]
name = "ruma-filter-removal-probe"
version = "0.1.0"
edition = "2021"
[dependencies]
ruma-client-api = { path = "$(pwd)/crates/ruma-client-api", features = ["client"] }
serde_json = "1"
EOF
  cat >"$PROBE_DIR/src/main.rs" <<'EOF'
use ruma_client_api::filter::IncomingRoomEventFilter;

fn main() {
    let ordinary: IncomingRoomEventFilter = serde_json::from_str(r#"{"limit":1}"#).unwrap();
    let ordinary_value = serde_json::to_value(ordinary).unwrap();
    assert_eq!(ordinary_value["limit"], 1);

    let cases = [
        r#"{"io.element.relation_types":["m.annotation"],"io.element.relation_senders":["@alice:example.org"]}"#,
        r#"{"related_by_rel_types":["m.annotation"],"related_by_senders":["@alice:example.org"]}"#,
    ];
    let mut retained_keys = Vec::new();
    for input in cases {
        if let Ok(filter) = serde_json::from_str::<IncomingRoomEventFilter>(input) {
            let value = serde_json::to_value(filter).unwrap();
            for key in ["io.element.relation_types", "io.element.relation_senders"] {
                if value.get(key).is_some() {
                    retained_keys.push(key);
                }
            }
        }
    }
    assert!(retained_keys.is_empty(), "removed filter keys were serialized: {retained_keys:?}");
}
EOF
  cargo run --offline --manifest-path "$PROBE_DIR/Cargo.toml" --quiet
  RESULT=$?
  rm -rf "$PROBE_DIR"
  test "$RESULT" -eq 0
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
