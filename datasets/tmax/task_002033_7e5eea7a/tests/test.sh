#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import hashlib
import importlib.machinery
import json
import os
import random
import shutil
import string
import subprocess
import sys
import tempfile
import uuid

import pytest

ORACLE_PATH = "/app/oracle/token_oracle"
AGENT_SCRIPT = "/home/user/token_rotator.py"
VENDORED = "/app/vendored/libsectoken-1.2.0"
CSP = "default-src 'none'; script-src 'self';"
NUM_ITERATIONS = 100


def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def generate_random_hex(length):
    return ''.join(random.choices(string.hexdigits.lower(), k=length))


def generate_random_json():
    num_keys = random.randint(1, 5)
    data = {}
    for _ in range(num_keys):
        key = generate_random_string(random.randint(4, 10))
        val_type = random.choice(['int', 'string', 'hex'])
        if val_type == 'int':
            data[key] = random.randint(1, 1000000)
        elif val_type == 'string':
            data[key] = generate_random_string(random.randint(5, 20))
        else:
            data[key] = generate_random_hex(random.randint(8, 32))
    return json.dumps(data)


def expected_token(input_json, signature=None):
    payload = f"{CSP}|{input_json}".encode()
    if signature is None:
        signature = hashlib.sha256(payload).digest()
    return base64.b64encode(payload + b"|" + signature).decode()


def run_agent(input_json, env=None, command=None, cwd=None):
    proc = subprocess.run(
        command or [sys.executable, AGENT_SCRIPT, input_json],
        capture_output=True,
        text=True,
        timeout=2,
        check=True,
        env=env,
        cwd=cwd,
    )
    return proc.stdout.strip()


def test_package_was_fixed_built_and_installed():
    source = os.path.join(VENDORED, "src", "sectoken.c")
    setup_py = os.path.join(VENDORED, "setup.py")
    assert os.path.isfile(source)
    assert os.path.isfile(setup_py)
    assert "<cyrpto.h>" not in open(source, encoding="utf-8").read()

    # Verify the package is already importable from outside its source tree and
    # that the installed artifact is a compiled extension with correct behavior.
    probe = r'''
import hashlib, importlib.machinery, json, libsectoken
p = "default-src 'none'; script-src 'self';|{\"probe\":17}"
origin = getattr(libsectoken, "__file__", "")
is_ext = any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
r = libsectoken.sign_payload(p)
print(json.dumps({"origin": origin, "is_ext": is_ext,
                  "is_bytes": isinstance(r, bytes),
                  "correct": r == hashlib.sha256(p.encode()).digest()}))
'''
    installed = subprocess.run(
        [sys.executable, "-c", probe], cwd="/tmp", capture_output=True,
        text=True, timeout=10, check=True
    )
    info = json.loads(installed.stdout)
    assert info["is_ext"], f"Installed libsectoken is not a compiled extension: {info['origin']}"
    assert info["is_bytes"] and info["correct"]

    # Rebuild from the repaired vendored sources, ensuring the actual build
    # defect is fixed rather than bypassed with an unrelated module.
    subprocess.run(
        [sys.executable, "setup.py", "build_ext", "--inplace", "--force"],
        cwd=VENDORED, capture_output=True, text=True, timeout=30, check=True
    )
    extensions = []
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        extensions.extend(glob.glob(os.path.join(VENDORED, "libsectoken*" + suffix)))
    assert extensions, "The repaired vendored package did not build libsectoken"
    linked = subprocess.run(
        ["ldd", extensions[0]], capture_output=True, text=True, timeout=5, check=True
    )
    assert "libcrypto" in linked.stdout.lower(), "libsectoken was not linked against libcrypto"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

    random.seed(42)
    for i in range(NUM_ITERATIONS):
        input_json = generate_random_json()
        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH, input_json], capture_output=True, text=True,
                timeout=2, check=True
            )
            oracle_output = oracle_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input '{input_json}'.\nStderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input '{input_json}'")

        try:
            agent_output = run_agent(input_json)
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input '{input_json}'.\nStderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input '{input_json}'")

        assert oracle_output == agent_output, (
            f"Mismatch on iteration {i+1}!\nInput: {input_json}\n"
            f"Oracle output: {oracle_output}\nAgent output:  {agent_output}"
        )


def test_independent_behavior_and_libsectoken_use():
    script_text = open(AGENT_SCRIPT, encoding="utf-8").read()
    assert ORACLE_PATH not in script_text, "The rotator must not invoke the oracle at runtime"

    hidden_oracle = os.path.join(
        os.path.dirname(ORACLE_PATH), ".token_oracle.verifier." + uuid.uuid4().hex
    )
    os.rename(ORACLE_PATH, hidden_oracle)
    try:
        # Derive expected values independently while the supplied oracle is unavailable.
        independent_inputs = [
            '{"user_id": 12345, "role": "admin"}',
            '{"empty":"","zero":0,"flag":true}',
            json.dumps({"nonce": generate_random_hex(31), "count": 987654}),
        ]
        for input_json in independent_inputs:
            assert run_agent(input_json) == expected_token(input_json)

        # Substitute a controlled libsectoken implementation and require its
        # returned signature to appear in the token. This rejects scripts that
        # merely import/call the library but ignore it.
        with tempfile.TemporaryDirectory() as shim_dir:
            marker = os.path.join(shim_dir, "called")
            shim = os.path.join(shim_dir, "libsectoken.py")
            with open(shim, "w", encoding="utf-8") as f:
                f.write(
                    "import os\n"
                    "def sign_payload(payload):\n"
                    "    data = payload.encode() if isinstance(payload, str) else bytes(payload)\n"
                    "    with open(os.environ['SECTOKEN_MARKER'], 'wb') as m: m.write(data)\n"
                    "    return b'\\xa5' * 32\n"
                )
            input_json = '{"library_use":"verified","n":314159}'
            env = os.environ.copy()
            env["PYTHONPATH"] = shim_dir
            env["SECTOKEN_MARKER"] = marker
            runner = (
                "import runpy,sys; "
                f"sys.argv=[{AGENT_SCRIPT!r},sys.argv[1]]; "
                f"runpy.run_path({AGENT_SCRIPT!r},run_name='__main__')"
            )
            output = run_agent(
                input_json, env=env,
                command=[sys.executable, "-c", runner, input_json], cwd=shim_dir
            )
            payload = f"{CSP}|{input_json}".encode()
            assert os.path.isfile(marker), "token_rotator.py did not call libsectoken.sign_payload"
            assert open(marker, "rb").read() == payload
            assert output == expected_token(input_json, b"\xa5" * 32), (
                "token_rotator.py did not use libsectoken's returned signature"
            )
    finally:
        if os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, ORACLE_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
