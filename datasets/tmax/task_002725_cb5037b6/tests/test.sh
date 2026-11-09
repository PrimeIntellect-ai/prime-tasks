#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import shutil
import subprocess
import tempfile

import pytest


def test_exploit_execution_and_proof():
    exploit_path = "/home/user/exploit.py"
    handler_path = "/home/user/app/handler.py"
    proof_path = "/home/user/proof.txt"
    upload_dir = "/home/user/app/uploads"

    assert os.path.isfile(exploit_path), f"Exploit script not found at {exploit_path}"

    private_dir = tempfile.mkdtemp(prefix="verify_handler_")
    original_handler = os.path.join(private_dir, "handler_original.py")
    invocation_log = os.path.join(private_dir, "invocations.jsonl")
    shutil.copy2(handler_path, original_handler)

    wrapper = f'''import json
import runpy
import sys

_ORIGINAL = {original_handler!r}
_LOG = {invocation_log!r}
_ns = runpy.run_path(_ORIGINAL)
_original_main = _ns["main"]
for _key, _value in _ns.items():
    if not _key.startswith("__") and _key != "main":
        globals()[_key] = _value

def main():
    with open(_LOG, "a") as _out:
        _out.write(json.dumps(sys.argv[1:]) + "\\n")
    return _original_main()

if __name__ == "__main__":
    main()
'''

    result = None
    records = []
    try:
        with open(handler_path, "w") as f:
            f.write(wrapper)
        os.chmod(handler_path, 0o755)

        if os.path.exists(proof_path):
            os.remove(proof_path)

        result = subprocess.run(
            ["python3", exploit_path], capture_output=True, text=True, timeout=20
        )

        if os.path.exists(invocation_log):
            with open(invocation_log, "r") as f:
                records = [json.loads(line) for line in f if line.strip()]
    finally:
        shutil.copy2(original_handler, handler_path)
        shutil.rmtree(private_dir, ignore_errors=True)

    assert result is not None
    assert result.returncode == 0, (
        f"Exploit script failed with exit code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )

    valid_invocation = False
    for argv in records:
        if not isinstance(argv, list) or len(argv) != 2:
            continue
        try:
            encrypted_filename = base64.b64decode(argv[0], validate=True).decode("utf-8")
            encrypted_content = base64.b64decode(argv[1], validate=True).decode("utf-8")
            filename = "".join(chr(ord(ch) ^ 42) for ch in encrypted_filename)
            content = "".join(chr(ord(ch) ^ 42) for ch in encrypted_content)
        except (ValueError, UnicodeDecodeError):
            continue

        destination = os.path.realpath(os.path.join(upload_dir, filename))
        if destination == proof_path and content == "EXPLOIT_SUCCESS":
            valid_invocation = True
            break

    assert valid_invocation, (
        "exploit.py did not invoke handler.py with base64/XOR encoded arguments "
        "that make the handler write EXPLOIT_SUCCESS to /home/user/proof.txt"
    )

    assert os.path.exists(proof_path), (
        f"Proof file was not created at {proof_path} after running exploit.py"
    )
    with open(proof_path, "r") as f:
        proof_content = f.read().strip()
    assert proof_content == "EXPLOIT_SUCCESS", (
        f"Expected proof.txt to contain 'EXPLOIT_SUCCESS', but got '{proof_content}'"
    )


def test_report_json():
    report_path = "/home/user/report.json"

    assert os.path.exists(report_path), f"Report file not found at {report_path}"

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON")

    assert "cwe" in data, "Report JSON missing 'cwe' key"
    assert data["cwe"] == "CWE-22", f"Expected 'cwe' to be 'CWE-22', got '{data['cwe']}'"

    assert "xor_key" in data, "Report JSON missing 'xor_key' key"
    assert data["xor_key"] == 42, f"Expected 'xor_key' to be 42, got {data['xor_key']}"


def test_handler_unmodified():
    handler_path = "/home/user/app/handler.py"
    assert os.path.exists(handler_path), f"Handler script {handler_path} is missing."
    with open(handler_path, "r") as f:
        content = f.read()
    assert "import base64,zlib,sys;exec(zlib.decompress(base64.b64decode(" in content, "Handler script appears to have been modified."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
