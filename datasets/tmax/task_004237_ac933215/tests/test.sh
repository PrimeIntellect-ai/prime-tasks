#!/bin/bash
set +e
mkdir -p /logs/verifier

TRACE_FILE=$(mktemp /tmp/meta_bridge_calls.XXXXXX)
ORIGINAL_BRIDGE=$(mktemp /app/.meta_bridge.verifier.XXXXXX)
rm -f "$ORIGINAL_BRIDGE"
RESTORE_BRIDGE=0

restore_bridge() {
    if [ "$RESTORE_BRIDGE" -eq 1 ] && [ -e "$ORIGINAL_BRIDGE" ]; then
        rm -f /app/meta_bridge
        mv -f "$ORIGINAL_BRIDGE" /app/meta_bridge
    fi
}
trap restore_bridge EXIT INT TERM

fail_verifier() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

mv /app/meta_bridge "$ORIGINAL_BRIDGE" || fail_verifier
RESTORE_BRIDGE=1
chmod 666 "$TRACE_FILE" || fail_verifier

cat > /app/meta_bridge <<EOF
#!/bin/sh
printf '%s\t%s\n' "\$#" "\${1-}" >> '$TRACE_FILE'
exec '$ORIGINAL_BRIDGE' "\$@"
EOF
chmod 755 /app/meta_bridge || fail_verifier

export TRACE_FILE ORIGINAL_BRIDGE

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import socket
import subprocess
import time
import pytest

TRACE_FILE = os.environ["TRACE_FILE"]
ORIGINAL_BRIDGE = os.environ["ORIGINAL_BRIDGE"]


def djb2_hash(s):
    hash_val = 5381
    for char in s:
        hash_val = ((hash_val << 5) + hash_val + ord(char)) & 0xFFFFFFFFFFFFFFFF
    return f"GRAPH_NODE_{hash_val:lx}"


def bridge_output(table):
    result = subprocess.run(
        [ORIGINAL_BRIDGE, table],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    return result.stdout.rstrip("\n")


def send_request_and_get_response(host, port, request_str):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((host, port))
        s.sendall(request_str.encode("utf-8"))
        response = s.recv(1024).decode("utf-8")
    return response


def trace_lines():
    with open(TRACE_FILE, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def test_wrapper_artifact_exists():
    candidates = [
        path for path in glob.glob("/home/user/service_wrapper*")
        if os.path.isfile(path) and os.path.getsize(path) > 0
    ]
    assert candidates, "No non-empty service wrapper file exists at /home/user/service_wrapper (with any extension)."


def test_service_responses_and_bridge_invocations():
    host = "127.0.0.1"
    port = 8081

    fixed_cases = [
        ("SELECT * FROM users JOIN orders ON users.id = orders.u_id\n", "users", "orders"),
        ("SELECT * FROM tableA JOIN tableB ON cond\n", "tableA", "tableB"),
        ("SELECT * FROM customers JOIN invoices ON c.id=i.cid\n", "customers", "invoices"),
    ]

    dynamic_cases = []
    for _ in range(4):
        t1 = "src_" + secrets.token_hex(12)
        t2 = "dst_" + secrets.token_hex(12)
        dynamic_cases.append((f"SELECT * FROM {t1} JOIN {t2} ON x=y\n", t1, t2))

    for index, (req, t1, t2) in enumerate(fixed_cases + dynamic_cases):
        if index < len(fixed_cases):
            expected_out1 = djb2_hash(t1)
            expected_out2 = djb2_hash(t2)
        else:
            expected_out1 = bridge_output(t1)
            expected_out2 = bridge_output(t2)
        expected_response = f"PIPELINE: {expected_out1} -> {expected_out2}\n"

        before = trace_lines()
        try:
            actual_response = send_request_and_get_response(host, port, req)
        except Exception as e:
            pytest.fail(f"Failed to communicate with service on {host}:{port} for request '{req.strip()}': {e}")

        assert actual_response == expected_response, \
            f"Expected response '{expected_response.strip()}', but got '{actual_response.strip()}'"

        after = trace_lines()
        new_calls = after[len(before):]
        assert new_calls == [f"1\t{t1}", f"1\t{t2}"], \
            f"Request must execute /app/meta_bridge exactly twice with one argument each; observed {new_calls!r}"


def test_log_file_exists_and_contains_requests():
    log_path = "/home/user/wrapper.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    assert os.path.isfile(log_path), f"Path {log_path} is not a file."

    with open(log_path, "r") as f:
        log_contents = f.read()

    assert "users" in log_contents or "orders" in log_contents or "tableA" in log_contents, \
        f"Log file {log_path} does not appear to contain the incoming requests."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

exit 0
