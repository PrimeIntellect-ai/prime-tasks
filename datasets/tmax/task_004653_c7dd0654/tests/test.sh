#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import base64
import hashlib
import hmac
import json
import os
import secrets
import stat
import subprocess
import sys

SCRIPT = "/home/user/analyze.py"
LOG = "/home/user/server.log"
KEY = "/home/user/secret.key"
OUTPUT = "/home/user/compromised_users.txt"
ORIGINAL_EXPECTED = [
    "10.0.0.2,bob",
    "10.0.0.4,charlie",
    "10.0.0.5,dave",
]


def read_nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def assert_original_output():
    assert os.path.isfile(OUTPUT), (
        f"Output file {OUTPUT} is missing. The script did not generate the required file."
    )
    actual_lines = read_nonempty_lines(OUTPUT)
    assert len(actual_lines) == len(ORIGINAL_EXPECTED), (
        f"Expected {len(ORIGINAL_EXPECTED)} compromised users, but found {len(actual_lines)}."
    )
    for i, expected in enumerate(ORIGINAL_EXPECTED):
        assert actual_lines[i] == expected, (
            f"Line {i+1} mismatch. Expected '{expected}', got '{actual_lines[i]}'."
        )


def run_script():
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"analyze.py exited with status {result.returncode}. stderr: {result.stderr}"
    )


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_token(username, secret, valid=True):
    payload = b64url(json.dumps({"username": username}, separators=(",", ":")).encode())
    signing_key = secret if valid else secrets.token_bytes(32)
    signature = b64url(hmac.new(signing_key, payload.encode("ascii"), hashlib.sha256).digest())
    return payload + "." + signature


# Preserve all original checks before the verifier changes any supplied data.
assert_original_output()

assert os.path.isfile(SCRIPT), f"Required script {SCRIPT} is missing."
mode = os.stat(SCRIPT).st_mode
assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file."
assert mode & 0o111, f"{SCRIPT} is not executable."

with open(SCRIPT, "rb") as f:
    source = f.read()
try:
    tree = ast.parse(source, filename=SCRIPT)
except (SyntaxError, UnicodeDecodeError) as exc:
    raise AssertionError(f"{SCRIPT} is not a valid Python program: {exc}")

# Enforce the stated standard-library-only restriction for ordinary imports.
stdlib = set(sys.stdlib_module_names)
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        modules = [alias.name.split(".", 1)[0] for alias in node.names]
    elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
        modules = [node.module.split(".", 1)[0]]
    else:
        continue
    for module in modules:
        assert module in stdlib, f"External module import is not allowed: {module}"

with open(LOG, "rb") as f:
    original_log = f.read()
with open(KEY, "rb") as f:
    original_key = f.read()
original_output = None
if os.path.exists(OUTPUT):
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

try:
    secret = secrets.token_bytes(32)
    marker = secrets.token_hex(8)
    users = [f"audit_{marker}_{i}" for i in range(6)]
    tokens = [make_token(user, secret) for user in users]

    records = [
        # Benign requests and near-matches must not be reported.
        {"timestamp":"t0","ip":"192.0.2.1","method":"POST","path":"/upload","headers":{"Cookie":f"session={tokens[0]}","X-Upload-Path":"images/safe"}},
        {"timestamp":"t1","ip":"192.0.2.2","method":"POST","path":"/upload/.../file","headers":{"Cookie":f"session={tokens[0]}"}},
        {"timestamp":"t2","ip":"192.0.2.3","method":"POST","path":"/upload/%2e%2f/file","headers":{"Cookie":f"session={tokens[0]}"}},
        # Each required traversal representation, across path and header.
        {"timestamp":"t3","ip":"198.51.100.10","method":"POST","path":"/upload/../etc/passwd","headers":{"Cookie":f"other=x; session={tokens[1]}; theme=dark"}},
        {"timestamp":"t4","ip":"198.51.100.11","method":"POST","path":"/upload","headers":{"Cookie":f"session={tokens[2]}","X-Upload-Path":"..\\windows\\system.ini"}},
        {"timestamp":"t5","ip":"198.51.100.12","method":"GET","path":"/download/%2E%2e%2Fsecret","headers":{"Cookie":f"session={tokens[3]}"}},
        {"timestamp":"t6","ip":"198.51.100.13","method":"POST","path":"/upload","headers":{"Cookie":f"session={tokens[4]}","X-Upload-Path":"dir/%2e%2E%5Cconfig"}},
        # Duplicate user/IP occurrences must be retained.
        {"timestamp":"t7","ip":"198.51.100.10","method":"POST","path":"../../again","headers":{"Cookie":f"session={tokens[1]}"}},
        # Traversal with invalid, missing, and malformed tokens must be ignored.
        {"timestamp":"t8","ip":"203.0.113.20","method":"POST","path":"../invalid","headers":{"Cookie":f"session={make_token(users[5], secret, valid=False)}"}},
        {"timestamp":"t9","ip":"203.0.113.21","method":"POST","path":"../missing","headers":{"Cookie":"theme=dark"}},
        {"timestamp":"t10","ip":"203.0.113.22","method":"POST","path":"../malformed","headers":{"Cookie":"session=not-a-token"}},
    ]
    expected = [
        f"198.51.100.10,{users[1]}",
        f"198.51.100.11,{users[2]}",
        f"198.51.100.12,{users[3]}",
        f"198.51.100.13,{users[4]}",
        f"198.51.100.10,{users[1]}",
    ]

    with open(KEY, "wb") as f:
        f.write(secret)
    with open(LOG, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    run_script()
    assert os.path.isfile(OUTPUT), "analyze.py did not create compromised_users.txt on supplied test data."
    actual = read_nonempty_lines(OUTPUT)
    assert actual == expected, f"Behavioral test mismatch. Expected {expected!r}, got {actual!r}."
finally:
    with open(LOG, "wb") as f:
        f.write(original_log)
    with open(KEY, "wb") as f:
        f.write(original_key)
    if original_output is None:
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
    else:
        with open(OUTPUT, "wb") as f:
            f.write(original_output)

# Execute the submitted artifact on the original inputs and retain the original assertions.
run_script()
assert_original_output()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
