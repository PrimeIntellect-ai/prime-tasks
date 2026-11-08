#!/bin/bash
set +e
mkdir -p /logs/verifier
PROJECT=/home/user/api-gateway
REWARD=/logs/verifier/reward.txt
FAILED=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def test_test_results_log_exists():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"Test results log {log_path} does not exist."


def test_test_results_indicate_success():
    log_path = "/home/user/test_results.log"
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert re.search(r'test result: ok\.', content) or re.search(r'\d+ passed', content), \
        "The test_results.log does not indicate successful test execution ('test result: ok.' or 'passed')."


def test_cargo_toml_conflict_resolved():
    cargo_path = "/home/user/api-gateway/Cargo.toml"
    assert os.path.isfile(cargo_path), f"{cargo_path} does not exist."
    with open(cargo_path, "r", encoding="utf-8") as f:
        content = f.read()
    has_tonic_09 = 'tonic = "0.9"' in content or "tonic = '0.9'" in content
    has_prost_12 = 'prost = "0.12"' in content or "prost = '0.12'" in content
    assert not (has_tonic_09 and has_prost_12), \
        "Cargo.toml still has the conflicting tonic 0.9 and prost 0.12 dependencies."


def test_rest_handler_implemented():
    rest_path = "/home/user/api-gateway/src/rest.rs"
    assert os.path.isfile(rest_path), f"{rest_path} does not exist."
    with open(rest_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Hasher" in content or "crc32fast" in content, \
        "src/rest.rs does not seem to use crc32fast for checksum calculation."
    assert "Path" in content, "src/rest.rs does not seem to extract the Path parameter."
    assert len(re.findall(r'forward_to_grpc\s*\(', content)) >= 2, \
        "relay_handler does not appear to call the provided gRPC forwarding stub."


def test_security_tests_implemented():
    tests_path = "/home/user/api-gateway/src/security_tests.rs"
    assert os.path.isfile(tests_path), f"{tests_path} does not exist."
    with open(tests_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "proptest!" in content or "proptest {" in content, \
        "src/security_tests.rs does not seem to contain a proptest block."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
if [ $? -ne 0 ]; then
    FAILED=1
fi

BACKUP_DIR=$(mktemp -d)
cp "$PROJECT/Cargo.toml" "$BACKUP_DIR/Cargo.toml"
if [ -f "$PROJECT/Cargo.lock" ]; then
    cp "$PROJECT/Cargo.lock" "$BACKUP_DIR/Cargo.lock"
    HAD_LOCK=1
else
    HAD_LOCK=0
fi
mkdir -p "$PROJECT/tests"
if [ -f "$PROJECT/tests/verifier_behavior.rs" ]; then
    cp "$PROJECT/tests/verifier_behavior.rs" "$BACKUP_DIR/verifier_behavior.rs"
    HAD_TEST=1
else
    HAD_TEST=0
fi

cleanup() {
    cp "$BACKUP_DIR/Cargo.toml" "$PROJECT/Cargo.toml"
    if [ "$HAD_LOCK" -eq 1 ]; then
        cp "$BACKUP_DIR/Cargo.lock" "$PROJECT/Cargo.lock"
    else
        rm -f "$PROJECT/Cargo.lock"
    fi
    if [ "$HAD_TEST" -eq 1 ]; then
        cp "$BACKUP_DIR/verifier_behavior.rs" "$PROJECT/tests/verifier_behavior.rs"
    else
        rm -f "$PROJECT/tests/verifier_behavior.rs"
    fi
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

python3 - << 'PY'
from pathlib import Path
import re
p = Path('/home/user/api-gateway/Cargo.toml')
s = p.read_text()
if not re.search(r'^tower\s*=', s, re.M):
    match = re.search(r'^\[dev-dependencies\]\s*$', s, re.M)
    if match:
        end = match.end()
        s = s[:end] + '\ntower = { version = "0.4", features = ["util"] }' + s[end:]
    else:
        s = s.rstrip() + '\n\n[dev-dependencies]\ntower = { version = "0.4", features = ["util"] }\n'
p.write_text(s)
PY
if [ $? -ne 0 ]; then
    FAILED=1
fi

cat << 'RUST_EOF' > "$PROJECT/tests/verifier_behavior.rs"
#[path = "../src/rest.rs"]
mod submitted_rest;

use axum::{
    body::Body,
    http::{Request, StatusCode},
    routing::post,
    Router,
};
use tower::ServiceExt;

fn crc32_decimal(payload: &[u8]) -> String {
    let mut hasher = crc32fast::Hasher::new();
    hasher.update(payload);
    hasher.finalize().to_string()
}

async fn request(payload: &[u8], checksum: Option<&str>) -> StatusCode {
    let app = Router::new().route(
        "/api/v1/relay/:id",
        post(submitted_rest::relay_handler),
    );
    let mut builder = Request::builder()
        .method("POST")
        .uri("/api/v1/relay/verifier-id");
    if let Some(value) = checksum {
        builder = builder.header("X-Checksum", value);
    }
    app.oneshot(builder.body(Body::from(payload.to_vec())).unwrap())
        .await
        .unwrap()
        .status()
}

#[tokio::test]
async fn verifier_accepts_correct_crc32_for_varied_raw_bodies() {
    let payloads: Vec<Vec<u8>> = vec![
        Vec::new(),
        b"gateway payload".to_vec(),
        "Unicode payload: λ雪".as_bytes().to_vec(),
        vec![0, 1, 2, 127, 128, 254, 255],
        (0u8..=255).collect(),
    ];
    for payload in payloads {
        let checksum = crc32_decimal(&payload);
        assert_eq!(request(&payload, Some(&checksum)).await, StatusCode::OK);
    }
}

#[tokio::test]
async fn verifier_rejects_missing_malformed_and_incorrect_checksums() {
    let payload = b"checksum rejection case";
    assert_eq!(request(payload, None).await, StatusCode::BAD_REQUEST);
    assert_eq!(request(payload, Some("not-a-u32")).await, StatusCode::BAD_REQUEST);
    let valid: u32 = crc32_decimal(payload).parse().unwrap();
    let wrong = valid.wrapping_add(1).to_string();
    assert_eq!(request(payload, Some(&wrong)).await, StatusCode::BAD_REQUEST);
}
RUST_EOF

cd "$PROJECT"
cargo test > /home/user/test_results.log 2>&1
if [ $? -ne 0 ]; then
    cat /home/user/test_results.log
    FAILED=1
fi

python3 - << 'PY'
import re
from pathlib import Path
log = Path('/home/user/test_results.log').read_text(errors='replace')
assert re.search(r'test result: ok\.', log), 'The verifier-run cargo test did not report success.'
assert re.search(r'test security_tests::tests::[^\s]+ \.\.\. ok', log), \
    'No passing property test from src/security_tests.rs was discovered by cargo test.'
PY
if [ $? -ne 0 ]; then
    FAILED=1
fi

if [ "$FAILED" -eq 0 ]; then
    echo "1" > "$REWARD"
else
    echo "0" > "$REWARD"
fi
