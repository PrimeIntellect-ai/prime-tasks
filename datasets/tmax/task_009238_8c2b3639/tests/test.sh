#!/bin/bash
set +e
mkdir -p /logs/verifier

export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo
export PATH="/opt/cargo/bin:$PATH"
export CARGO_TARGET_DIR="/tmp/grpc_verifier_target_$$"

BASE_DIR=/home/user/grpc_refactor_pr
STATUS=0
SERVER_PID=""
INPUT_BACKUP="/tmp/grpc_input_backup_$$.json"

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        SERVER_PID=""
    fi
    if [ -f "$INPUT_BACKUP" ]; then
        cp "$INPUT_BACKUP" "$BASE_DIR/input.json"
    fi
    rm -rf "$CARGO_TARGET_DIR"
}

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

BASE_DIR = "/home/user/grpc_refactor_pr"

def test_workflow_fixed():
    """Verify the GitHub Actions workflow file has the corrected commands."""
    workflow_path = os.path.join(BASE_DIR, ".github", "workflows", "rust.yml")
    assert os.path.isfile(workflow_path), f"Missing github workflow at {workflow_path}"

    with open(workflow_path, "r") as f:
        content = f.read()

    assert "cargo fmt --check" in content, "Workflow missing corrected 'cargo fmt --check' command"
    assert "cargo test" in content, "Workflow missing corrected 'cargo test' command"
    assert "cargo build --release" in content, "Workflow missing corrected 'cargo build --release' command"

    assert "cargo fmt --chek" not in content, "Workflow still contains broken 'cargo fmt --chek'"
    assert "cargo tesst" not in content, "Workflow still contains broken 'cargo tesst'"
    assert "cargo buid" not in content, "Workflow still contains broken 'cargo buid'"

def test_common_crate_exists():
    """Verify that the common crate was created."""
    common_cargo_path = os.path.join(BASE_DIR, "common", "Cargo.toml")
    assert os.path.isfile(common_cargo_path), f"Missing common crate Cargo.toml at {common_cargo_path}"

def test_dependencies_fixed():
    """Verify that the circular dependency is resolved and both depend on common."""
    client_cargo = os.path.join(BASE_DIR, "client", "Cargo.toml")
    server_cargo = os.path.join(BASE_DIR, "server", "Cargo.toml")

    assert os.path.isfile(client_cargo), f"Missing client Cargo.toml at {client_cargo}"
    assert os.path.isfile(server_cargo), f"Missing server Cargo.toml at {server_cargo}"

    with open(client_cargo, "r") as f:
        client_content = f.read()

    with open(server_cargo, "r") as f:
        server_content = f.read()

    # Check client dependencies
    assert "server =" not in client_content and "server=" not in client_content, \
        "Client still depends on server"
    assert "common" in client_content, "Client does not depend on common crate"

    # Check server dependencies
    assert "client =" not in server_content and "client=" not in server_content, \
        "Server still depends on client"
    assert "common" in server_content, "Server does not depend on common crate"

def test_verification_log():
    """Verify the client successfully parsed the JSON, called the server, and logged the output."""
    log_path = "/home/user/verification.log"
    assert os.path.isfile(log_path), f"Missing verification log at {log_path}. Did you run the client and save the output?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_output = "RESPONSE=Processed secret_data_99 with config retries 3"
    assert expected_output in content, f"Verification log does not contain the expected output. Found: {content}"
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
    STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
    if [ ! -f "$BASE_DIR/input.json" ]; then
        echo "Missing input.json" >&2
        STATUS=1
    else
        cp "$BASE_DIR/input.json" "$INPUT_BACKUP" || STATUS=1
    fi
fi

# Compile the entire workspace, which also exercises tonic-build and the proto file.
if [ "$STATUS" -eq 0 ]; then
    if ! cd "$BASE_DIR" || ! timeout 300 cargo build --workspace; then
        echo "cargo build --workspace failed" >&2
        STATUS=1
    fi
fi

# Use a verifier-generated input so a self-reported, hardcoded log cannot pass.
if [ "$STATUS" -eq 0 ]; then
    python3 - << 'PY'
import json
import secrets

payload = 'audit_' + secrets.token_hex(16) + '_quoted"_backslash\\_unicode_λ'
data = {
    'id': secrets.randbelow(2_000_000_000) + 1,
    'payload': payload,
    'is_active': bool(secrets.randbits(1)),
}
with open('/home/user/grpc_refactor_pr/input.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False)
with open('/tmp/grpc_expected_output', 'w', encoding='utf-8') as f:
    f.write('RESPONSE=Processed ' + payload + ' with config retries 3\n')
PY
    if [ "$?" -ne 0 ]; then
        STATUS=1
    fi
fi

if [ "$STATUS" -eq 0 ]; then
    "$CARGO_TARGET_DIR/debug/server" >/tmp/grpc_server_stdout 2>/tmp/grpc_server_stderr &
    SERVER_PID=$!

    CLIENT_OK=0
    for _ in $(seq 1 40); do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            break
        fi
        timeout 8 "$CARGO_TARGET_DIR/debug/client" >/tmp/grpc_client_stdout 2>/tmp/grpc_client_stderr
        RC=$?
        if [ "$RC" -eq 0 ]; then
            CLIENT_OK=1
            break
        fi
        sleep 0.25
    done

    if [ "$CLIENT_OK" -ne 1 ]; then
        echo "Client did not successfully call the running server" >&2
        cat /tmp/grpc_server_stderr >&2 2>/dev/null
        cat /tmp/grpc_client_stderr >&2 2>/dev/null
        STATUS=1
    elif ! cmp -s /tmp/grpc_client_stdout /tmp/grpc_expected_output; then
        echo "Client stdout did not match the response derived from verifier-generated JSON" >&2
        echo "Expected:" >&2
        cat /tmp/grpc_expected_output >&2
        echo "Actual:" >&2
        cat /tmp/grpc_client_stdout >&2
        STATUS=1
    fi
fi

# Wrong JSON field types must not be accepted as a valid structured request.
if [ "$STATUS" -eq 0 ]; then
    cat > "$BASE_DIR/input.json" << 'EOF'
{"id":"not-an-integer","payload":"malformed_id_probe","is_active":true}
EOF
    timeout 8 "$CARGO_TARGET_DIR/debug/client" >/tmp/grpc_bad_id_stdout 2>/tmp/grpc_bad_id_stderr
    if [ "$?" -eq 0 ]; then
        echo "Client accepted a non-integer id" >&2
        STATUS=1
    fi
fi

if [ "$STATUS" -eq 0 ]; then
    cat > "$BASE_DIR/input.json" << 'EOF'
{"id":123,"payload":"malformed_bool_probe","is_active":"not-a-boolean"}
EOF
    timeout 8 "$CARGO_TARGET_DIR/debug/client" >/tmp/grpc_bad_bool_stdout 2>/tmp/grpc_bad_bool_stderr
    if [ "$?" -eq 0 ]; then
        echo "Client accepted a non-boolean is_active value" >&2
        STATUS=1
    fi
fi

# Confirm that the successful client behavior really depends on a live gRPC server.
if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
    sleep 0.25
fi

if [ "$STATUS" -eq 0 ]; then
    python3 - << 'PY'
import json
with open('/home/user/grpc_refactor_pr/input.json', 'w', encoding='utf-8') as f:
    json.dump({'id': 7, 'payload': 'offline_probe', 'is_active': True}, f)
PY
    timeout 8 "$CARGO_TARGET_DIR/debug/client" >/tmp/grpc_offline_stdout 2>/tmp/grpc_offline_stderr
    if [ "$?" -eq 0 ]; then
        echo "Client succeeded without the gRPC server running" >&2
        STATUS=1
    fi
fi

cleanup

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
