#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import re
import secrets
import subprocess
import urllib.error
import urllib.request

import pytest
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

EVIL_DIR = "/home/user/app/corpora/evil"
CLEAN_DIR = "/home/user/app/corpora/clean"
MAIN_PATH = "/home/user/app/api/main.py"
NGINX_PATH = "/home/user/app/nginx/nginx.conf"
URL = "http://127.0.0.1:8080/api/execute"
BACKEND_URL = "http://127.0.0.1:5000/api/execute"
FORBIDDEN = {"syscall", "int", "int3", "sysenter"}


def send_request(payload, url=URL):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), dict(exc.headers)
    except urllib.error.URLError:
        return 0, b"", {}


def decode_json(body):
    try:
        return json.loads(body.decode("utf-8"))
    except Exception as exc:
        pytest.fail(f"Response body is not valid JSON: {body!r} ({exc})")


def assert_result(hex_code, expected_status):
    status, body, _ = send_request({"hex_code": hex_code})
    assert status == expected_status, f"{hex_code}: expected {expected_status}, got {status}; body={body!r}"
    parsed = decode_json(body)
    if expected_status == 403:
        assert parsed == {"error": "Malicious code detected"}, f"Incorrect 403 body for {hex_code}: {parsed!r}"
    else:
        assert parsed == {"status": "safe"}, f"Incorrect 200 body for {hex_code}: {parsed!r}"


def capstone_status(hex_code):
    code = bytes.fromhex(hex_code)
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    mnemonics = [instruction.mnemonic.lower() for instruction in md.disasm(code, 0)]
    return 403 if any(mnemonic in FORBIDDEN for mnemonic in mnemonics) else 200


def test_required_artifacts_and_services():
    assert os.path.isfile(MAIN_PATH), f"Missing backend artifact: {MAIN_PATH}"
    assert os.path.isfile(NGINX_PATH), f"Missing nginx artifact: {NGINX_PATH}"

    with open(MAIN_PATH, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=MAIN_PATH)
    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.add(node.module.split(".")[0])
    assert "capstone" in imports, "The backend must use the capstone library."

    with open(NGINX_PATH, "r", encoding="utf-8") as handle:
        nginx_conf = handle.read()
    assert re.search(r"\blisten\s+8080\s*;", nginx_conf), "nginx must listen on port 8080"
    assert re.search(r"\blocation\s+/api/\s*\{", nginx_conf), "nginx must define the /api/ location"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;", nginx_conf), "nginx must proxy to 127.0.0.1:5000"
    checked = subprocess.run(
        ["nginx", "-t", "-c", NGINX_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert checked.returncode == 0, f"Invalid nginx configuration:\n{checked.stdout}"

    status, body, headers = send_request({"hex_code": "90"})
    assert status != 0, f"Could not connect to Nginx at {URL}. Ensure Nginx and the Python API are running."
    assert status == 200 and decode_json(body) == {"status": "safe"}
    assert "nginx" in headers.get("Server", "").lower(), "Port 8080 response did not come through nginx"

    backend_status, _, _ = send_request({"hex_code": "90"}, BACKEND_URL)
    assert backend_status == 200, "The Python backend is not reachable on 127.0.0.1:5000"


def test_adversarial_corpus():
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith(".json")]
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith(".json")]

    assert len(evil_files) > 0, f"Evil corpus is empty in {EVIL_DIR}."
    assert len(clean_files) > 0, f"Clean corpus is empty in {CLEAN_DIR}."

    bypassed_evil = []
    for filename in evil_files:
        with open(os.path.join(EVIL_DIR, filename), "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        status, _, _ = send_request(payload)
        if status != 403:
            bypassed_evil.append(filename)

    modified_clean = []
    for filename in clean_files:
        with open(os.path.join(CLEAN_DIR, filename), "r", encoding="utf-8") as handle:
            payload = json.load(handle)
        status, _, _ = send_request(payload)
        if status != 200:
            modified_clean.append(filename)

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_canonical_and_generated_capstone_cases():
    # Independently retain the original corpus expectations so replacing the
    # writable corpus cannot weaken verification.
    for hex_code in ("0f05", "909090cd80", "cc", "0f34"):
        assert_result(hex_code, 403)
    for hex_code in ("4831c0", "4883c408", "90909090", "4889e5"):
        assert_result(hex_code, 200)

    # Every item is a complete x86_64 instruction. Several safe MOV immediates
    # contain the forbidden opcode bytes, preventing byte-substring filtering.
    safe_instructions = [
        "90", "6690", "4831c0", "4831db", "4831d2", "4889e5",
        "4883c001", "4883e801", "48ffc0", "48ffc8", "21c0", "09d8",
        "b80f050000", "b8cd800000", "b8cc000000", "b80f340000",
        "48b8050fcd80cc340f00",
    ]
    evil_instructions = ["0f05", "cd80", "cd03", "cc", "0f34"]
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    cases = set()

    for _ in range(80):
        parts = [rng.choice(safe_instructions) for _ in range(rng.randint(2, 8))]
        cases.add("".join(parts))
    for _ in range(80):
        parts = [rng.choice(safe_instructions) for _ in range(rng.randint(1, 5))]
        parts.insert(rng.randrange(len(parts) + 1), rng.choice(evil_instructions))
        parts.extend(rng.choice(safe_instructions) for _ in range(rng.randint(0, 4)))
        cases.add("".join(parts))

    expected_statuses = {capstone_status(case) for case in cases}
    assert expected_statuses == {200, 403}, "Generated suite must contain safe and malicious programs"
    for hex_code in cases:
        assert_result(hex_code, capstone_status(hex_code))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
