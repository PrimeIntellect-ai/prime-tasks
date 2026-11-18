#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import secrets
import stat
import subprocess
import tempfile

ORIGINAL_SOURCE = b'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void decode_and_write(const char *filename, const char *b64_payload) {
    char filepath[512];
    snprintf(filepath, sizeof(filepath), "/home/user/uploader/uploads/%s", filename);

    char command[1024];
    // Vulnerable to command injection too if we aren't careful, but let's assume standard input
    snprintf(command, sizeof(command), "echo '%s' | base64 -d > '%s'", b64_payload, filepath);
    system(command);
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <filename> <base64_payload>\\n", argv[0]);
        return 1;
    }
    decode_and_write(argv[1], argv[2]);
    return 0;
}
'''


def test_audit_hash():
    hash_file = "/home/user/audit_hash.txt"
    assert os.path.isfile(hash_file), f"{hash_file} does not exist."

    with open(hash_file, "r") as f:
        content = f.read().strip()

    assert len(content) == 64, f"The content of {hash_file} does not look like a valid SHA256 hash."
    assert all(c in "0123456789abcdefABCDEF" for c in content), f"The content of {hash_file} contains non-hexadecimal characters."
    expected = hashlib.sha256(ORIGINAL_SOURCE).hexdigest()
    assert content.lower() == expected, "audit_hash.txt is not the SHA256 hash of the original uploader.c."


def test_poc_script():
    poc_script = "/home/user/poc.sh"
    target_file = "/home/user/target.txt"
    uploader = "/home/user/uploader/uploader"

    assert os.path.isfile(poc_script), f"{poc_script} does not exist."
    assert os.access(poc_script, os.X_OK), f"{poc_script} is not executable."
    assert os.path.isfile(uploader), f"{uploader} does not exist."

    if os.path.exists(target_file):
        os.remove(target_file)

    with tempfile.TemporaryDirectory(prefix="verify_poc_") as td:
        real_uploader = os.path.join(td, "original_uploader")
        uploader_log = os.path.join(td, "uploader.jsonl")
        base64_log = os.path.join(td, "base64.jsonl")
        bin_dir = os.path.join(td, "bin")
        os.mkdir(bin_dir)

        base64_wrapper = os.path.join(bin_dir, "base64")
        with open(base64_wrapper, "w") as f:
            f.write(r'''#!/usr/bin/python3
import base64
import json
import os
import subprocess
import sys

raw = sys.stdin.buffer.read()
args = sys.argv[1:]
decode = any(a in ("-d", "--decode") for a in args)
if decode:
    with open(os.environ["VERIFY_BASE64_LOG"], "a") as log:
        log.write(json.dumps({"kind": "decode", "args": args, "input_b64": base64.b64encode(raw).decode()}) + "\n")
    result = subprocess.run(["/usr/bin/base64"] + args, input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    raise SystemExit(result.returncode)

result = subprocess.run(["/usr/bin/base64"] + args, input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if result.returncode != 0:
    sys.stderr.buffer.write(result.stderr)
    raise SystemExit(result.returncode)
encoded = b"".join(result.stdout.split())
k = 1 + (int(os.environ["VERIFY_NONCE"], 16) % (len(encoded) - 1))
token = encoded[:k] + b" \t" + encoded[k:]
with open(os.environ["VERIFY_BASE64_LOG"], "a") as log:
    log.write(json.dumps({"kind": "encode", "args": args, "input_b64": base64.b64encode(raw).decode(), "output": token.decode()}) + "\n")
sys.stdout.buffer.write(token + b"\n")
''')
        os.chmod(base64_wrapper, 0o755)

        os.replace(uploader, real_uploader)
        try:
            with open(uploader, "w") as f:
                f.write(r'''#!/usr/bin/python3
import json
import os
import sys
with open(os.environ["VERIFY_UPLOADER_LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\n")
os.execv(os.environ["VERIFY_REAL_UPLOADER"], [os.environ["VERIFY_REAL_UPLOADER"]] + sys.argv[1:])
''')
            os.chmod(uploader, 0o755)

            env = os.environ.copy()
            env["PATH"] = bin_dir + os.pathsep + env.get("PATH", "")
            env["VERIFY_BASE64_LOG"] = base64_log
            env["VERIFY_UPLOADER_LOG"] = uploader_log
            env["VERIFY_REAL_UPLOADER"] = real_uploader
            env["VERIFY_NONCE"] = secrets.token_hex(16)
            result = subprocess.run(["bash", poc_script], capture_output=True, text=True, env=env, timeout=15)
        finally:
            if os.path.lexists(uploader):
                os.remove(uploader)
            os.replace(real_uploader, uploader)

        assert os.path.isfile(target_file), f"PoC script did not create {target_file}. stdout={result.stdout!r}, stderr={result.stderr!r}"
        with open(target_file, "rb") as f:
            target_content = f.read()
        assert target_content.strip() == b"EXPLOIT_SUCCESS", f"Target file contains {target_content!r} instead of 'EXPLOIT_SUCCESS'."
        assert target_content == b"EXPLOIT_SUCCESS", "The target must contain the exact text EXPLOIT_SUCCESS."

        assert os.path.isfile(uploader_log), "PoC did not invoke /home/user/uploader/uploader."
        with open(uploader_log) as f:
            uploader_calls = [json.loads(line) for line in f if line.strip()]
        assert uploader_calls, "PoC did not invoke the existing uploader binary."

        assert os.path.isfile(base64_log), "PoC did not dynamically invoke base64."
        with open(base64_log) as f:
            base64_calls = [json.loads(line) for line in f if line.strip()]
        expected_input = base64.b64encode(b"EXPLOIT_SUCCESS").decode()
        encodes = [r for r in base64_calls if r.get("kind") == "encode" and r.get("input_b64") == expected_input]
        assert encodes, "PoC did not dynamically base64-encode the exact EXPLOIT_SUCCESS payload."

        matched = False
        for call in uploader_calls:
            if len(call) != 2:
                continue
            filename, payload = call
            destination = os.path.realpath(os.path.join("/home/user/uploader/uploads", filename))
            if destination == target_file and any(payload == record["output"] for record in encodes):
                matched = True
                break
        assert matched, "PoC must pass the dynamically encoded payload and a traversal filename to the existing uploader binary."


def test_uploads_permissions():
    uploads_dir = "/home/user/uploader/uploads"
    assert os.path.isdir(uploads_dir), f"{uploads_dir} does not exist."

    st = os.stat(uploads_dir)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Permissions of {uploads_dir} are {oct(perms)}, expected 0o700."


def run_fixed(binary, filename, payload):
    return subprocess.run([binary, filename, base64.b64encode(payload).decode()], capture_output=True, text=True, timeout=10)


def test_uploader_fixed_binary():
    fixed_binary = "/home/user/uploader_fixed"
    assert os.path.isfile(fixed_binary), f"{fixed_binary} does not exist."
    assert os.access(fixed_binary, os.X_OK), f"{fixed_binary} is not executable."
    with open(fixed_binary, "rb") as f:
        assert f.read(4) == bytes([0x7f]) + b"ELF", f"{fixed_binary} is not a compiled executable."

    res1 = subprocess.run([fixed_binary, "../test.txt", "dGVzdA=="], capture_output=True, text=True)
    assert res1.returncode == 1, f"Expected exit code 1 when filename contains '/', got {res1.returncode}."
    assert "Access Denied" in res1.stdout, "Expected 'Access Denied' in stdout when filename contains '/'."

    res2 = subprocess.run([fixed_binary, "test.txt", "dGVzdA=="], capture_output=True, text=True)
    assert res2.returncode == 1, f"Expected exit code 1 when filename contains '.', got {res2.returncode}."
    assert "Access Denied" in res2.stdout, "Expected 'Access Denied' in stdout when filename contains '.'."

    test_file = "/home/user/uploader/uploads/test"
    if os.path.exists(test_file):
        os.remove(test_file)
    res3 = subprocess.run([fixed_binary, "test", "dGVzdA=="], capture_output=True, text=True)
    assert res3.returncode == 0, f"Expected exit code 0 for valid filename, got {res3.returncode}."
    assert os.path.isfile(test_file), f"Expected {test_file} to be created for valid filename."
    with open(test_file, "r") as f:
        content = f.read().strip()
    assert content == "test", f"Expected decoded payload 'test' in {test_file}, got '{content}'."

    nonce = secrets.token_hex(12)
    invalid_names = [
        f"{nonce}/child", f"parent/{nonce}", f"{nonce}//child",
        f"{nonce}.txt", f".{nonce}", f"{nonce}..backup",
        f"safe_{nonce}/../escape", f"safe-{nonce}.part",
    ]
    for name in invalid_names:
        result = run_fixed(fixed_binary, name, secrets.token_bytes(19))
        assert result.returncode == 1, f"Expected exit code 1 for invalid filename {name!r}, got {result.returncode}."
        assert "Access Denied" in result.stdout, f"Expected 'Access Denied' in stdout for {name!r}."

    for i in range(8):
        name = f"valid_{nonce}_{i}_{secrets.token_hex(4)}"
        payload = secrets.token_bytes(8 + i)
        output = os.path.join("/home/user/uploader/uploads", name)
        if os.path.exists(output):
            os.remove(output)
        result = run_fixed(fixed_binary, name, payload)
        assert result.returncode == 0, f"Expected exit code 0 for valid filename {name!r}, got {result.returncode}."
        assert os.path.isfile(output), f"Expected {output} to be created."
        with open(output, "rb") as f:
            assert f.read() == payload, f"Decoded payload was incorrect for valid filename {name!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
