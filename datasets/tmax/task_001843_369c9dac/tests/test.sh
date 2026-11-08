#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

if (
    set -e

    cd /home/user/rust_eval
    cargo build

    cd /home/user/cpp_cache
    g++ -o cacher main.cpp
    g++ -fsanitize=address,undefined -fno-omit-frame-pointer -g -o /tmp/cacher_sanitized main.cpp

    rm -f /tmp/verifier_evaluator.log /tmp/verifier_cacher.log /tmp/verifier_signer.log
    touch /tmp/verifier_evaluator.log /tmp/verifier_cacher.log /tmp/verifier_signer.log
    chmod 666 /tmp/verifier_evaluator.log /tmp/verifier_cacher.log /tmp/verifier_signer.log

    rm -f /home/user/rust_eval/target/debug/evaluator.verifier_real
    mv /home/user/rust_eval/target/debug/evaluator /home/user/rust_eval/target/debug/evaluator.verifier_real
    cat > /home/user/rust_eval/target/debug/evaluator <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> /tmp/verifier_evaluator.log
exec /home/user/rust_eval/target/debug/evaluator.verifier_real "$@"
EOF
    chmod 755 /home/user/rust_eval/target/debug/evaluator

    rm -f /home/user/cpp_cache/cacher.verifier_real
    mv /home/user/cpp_cache/cacher /home/user/cpp_cache/cacher.verifier_real
    cat > /home/user/cpp_cache/cacher <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> /tmp/verifier_cacher.log
exec /home/user/cpp_cache/cacher.verifier_real "$@"
EOF
    chmod 755 /home/user/cpp_cache/cacher

    rm -f /app/mobile_signer.verifier_real
    mv /app/mobile_signer /app/mobile_signer.verifier_real
    cat > /app/mobile_signer <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> /tmp/verifier_signer.log
exec /app/mobile_signer.verifier_real "$@"
EOF
    chmod 755 /app/mobile_signer

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import subprocess

import pytest
import requests

RUST_BIN = "/home/user/rust_eval/target/debug/evaluator"
CACHE_BIN = "/home/user/cpp_cache/cacher"


def read_log(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def test_ready_file_contains_ready():
    assert os.path.exists("/home/user/ready.txt"), \
        "The /home/user/ready.txt file does not exist. Did you write it after starting the service?"
    with open("/home/user/ready.txt", "r", encoding="utf-8") as f:
        assert f.read().strip() == "READY", "/home/user/ready.txt must contain READY"


def test_compiled_tools_directly_and_large_cache_input():
    nonce = secrets.token_hex(12)
    expr = f"FEATURE_{nonce} & (IOS_{nonce} | ANDROID_{nonce})"
    rust = subprocess.run(
        [RUST_BIN, expr], capture_output=True, text=True, timeout=10, check=True
    )
    lines = rust.stdout.splitlines()
    assert lines, "Rust evaluator produced no output"
    assert json.loads(lines[-1]) == {"parsed_expr": expr}

    cache_data = ("large_" + nonce + "_") * 5000
    cache = subprocess.run(
        [CACHE_BIN, cache_data], capture_output=True, text=True, timeout=15, check=True
    )
    assert cache.stdout.strip() == cache_data + "_hashed"

    sanitized_data = ("sanitized_" + nonce + "_") * 3000
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
    sanitized = subprocess.run(
        ["/tmp/cacher_sanitized", sanitized_data],
        capture_output=True,
        text=True,
        timeout=15,
        env=env,
    )
    assert sanitized.returncode == 0, (
        f"Sanitizers reported a memory-safety problem. stderr: {sanitized.stderr}"
    )
    assert sanitized.stdout.strip() == sanitized_data + "_hashed"


def call_api(payload):
    try:
        response = requests.post(
            "http://127.0.0.1:8080/process", json=payload, timeout=15
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the orchestrator API at 127.0.0.1:8080: {e}")

    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    assert "ast" in data, f"Response JSON missing 'ast' key. Got: {data}"
    assert "hash" in data, f"Response JSON missing 'hash' key. Got: {data}"
    assert "signature" in data, f"Response JSON missing 'signature' key. Got: {data}"
    return data


def test_orchestrator_api_fixed_and_unpredictable_requests():
    cases = []

    fixed_path = "/tmp/test_artifact.bin"
    fixed_content = b"verification_payload_123"
    with open(fixed_path, "wb") as f:
        f.write(fixed_content)
    cases.append(("A & (B | C)", "cache_key_999", fixed_path, fixed_content))

    for index in range(2):
        nonce = secrets.token_hex(16)
        expr = f"TARGET_{nonce} | (DEBUG_{nonce} & MOBILE_{index}_{nonce})"
        cache_data = f"cache_{index}_{nonce}_" + secrets.token_hex(128 + index * 64)
        file_path = f"/tmp/orchestrator_artifact_{index}_{nonce}.bin"
        content = os.urandom(257 + index * 4093) + nonce.encode("ascii")
        with open(file_path, "wb") as f:
            f.write(content)
        cases.append((expr, cache_data, file_path, content))

    for expr, cache_data, file_path, content in cases:
        data = call_api({
            "expr": expr,
            "cache_data": cache_data,
            "file_path": file_path,
        })
        expected_ast = {"parsed_expr": expr}
        assert data["ast"] == expected_ast, (
            f"Unexpected 'ast' value. Expected {expected_ast}, got {data['ast']}"
        )
        expected_hash = cache_data + "_hashed"
        assert data["hash"] == expected_hash, (
            f"Unexpected 'hash' value. Expected '{expected_hash}', got '{data['hash']}'"
        )
        expected_signature = hashlib.sha256(content).hexdigest()
        assert data["signature"] == expected_signature, (
            f"Unexpected 'signature' value. Expected '{expected_signature}', "
            f"got '{data['signature']}'"
        )

    evaluator_calls = read_log("/tmp/verifier_evaluator.log")
    cacher_calls = read_log("/tmp/verifier_cacher.log")
    signer_calls = read_log("/tmp/verifier_signer.log")
    for expr, cache_data, file_path, _ in cases:
        assert expr in evaluator_calls, "The API did not invoke the Rust evaluator with the request expression"
        assert cache_data in cacher_calls, "The API did not invoke the C++ cacher with the request data"
        assert file_path in signer_calls, "The API did not invoke /app/mobile_signer with the requested file"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
