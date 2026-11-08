#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

import pytest

WORKSPACE_DIR = "/home/user/workspace"
VALID_PAYLOADS_FILE = os.path.join(WORKSPACE_DIR, "valid_payloads.json")
LIBSECCHECK_SO = os.path.join(WORKSPACE_DIR, "libseccheck.so")
LIBSECCHECK_C = os.path.join(WORKSPACE_DIR, "libseccheck.c")
PATCH_FILE = os.path.join(WORKSPACE_DIR, "security_fix.patch")
DEPLOY_PREP_PY = os.path.join(WORKSPACE_DIR, "deploy_prep.py")
PAYLOAD_DIR = os.path.join(WORKSPACE_DIR, "payloads")


def test_libseccheck_so_exists():
    assert os.path.isfile(LIBSECCHECK_SO), f"Compiled shared library {LIBSECCHECK_SO} is missing."


def test_deploy_prep_script_exists():
    assert os.path.isfile(DEPLOY_PREP_PY), f"Python script {DEPLOY_PREP_PY} is missing."


def test_valid_payloads_json_exists():
    assert os.path.isfile(VALID_PAYLOADS_FILE), f"Output file {VALID_PAYLOADS_FILE} is missing. Did you execute the script?"


def test_valid_payloads_content():
    assert os.path.isfile(VALID_PAYLOADS_FILE), f"Cannot test content, {VALID_PAYLOADS_FILE} is missing."
    with open(VALID_PAYLOADS_FILE, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {VALID_PAYLOADS_FILE} does not contain valid JSON.")

    expected_ids = ["config_alpha", "config_delta"]
    assert isinstance(data, list), f"Expected a JSON array in {VALID_PAYLOADS_FILE}, but got {type(data).__name__}."
    assert data == expected_ids, f"Expected {expected_ids}, but got {data}. Ensure the C function's logic is correctly applied to the payloads."


def test_patch_is_applied_to_source():
    assert os.path.isfile(LIBSECCHECK_C), "libseccheck.c is missing."
    with open(LIBSECCHECK_C, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"int\s+check_payload\s*\(\s*const\s+char\s*\*\s*payload\s*,\s*int\s+length\s*\)", source), \
        "libseccheck.c does not contain the patched two-argument ABI."

    result = subprocess.run(
        ["patch", "--dry-run", "-R", "-p0", "-i", PATCH_FILE],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert result.returncode == 0, "security_fix.patch does not appear to have been applied to libseccheck.c:\n" + result.stdout


def test_submitted_shared_library_behavior():
    helper = r'''
import ctypes
import json
import sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.check_payload
fn.argtypes = [ctypes.c_char_p, ctypes.c_int]
fn.restype = ctypes.c_int
cases = [
    (b"ordinary safe payload", 21),
    (b"prefix <script>alert(1)</script> suffix", 0),
    (b"a" * 100, 1),
    (b"b" * 101, 0),
    (("é" * 60).encode("utf-8"), 0),
]
results = [fn(value, len(value)) for value, _ in cases]
expected = [expected for _, expected in cases]
if results != expected:
    raise SystemExit("unexpected results: %r; expected %r" % (results, expected))
'''
    result = subprocess.run(
        [sys.executable, "-c", helper, LIBSECCHECK_SO],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert result.returncode == 0, "libseccheck.so is not a loadable, correctly patched shared library:\n" + result.stdout


def _remove_path(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.unlink(path)


def test_deploy_script_executes_library_with_updated_abi():
    temp_root = tempfile.mkdtemp(prefix="seccheck_verify_")
    saved_library = os.path.join(temp_root, "submitted_libseccheck.so")
    saved_payloads = os.path.join(temp_root, "payloads")
    saved_output = os.path.join(temp_root, "valid_payloads.json")
    probe_source = os.path.join(temp_root, "probe.c")
    probe_library = os.path.join(temp_root, "probe.so")

    marker = "VERIFY_" + secrets.token_hex(10)
    ids = ["id_" + secrets.token_hex(8) for _ in range(4)]
    payloads = [
        {"id": ids[0], "data": marker + "_ascii_safe"},
        {"id": ids[1], "data": "ordinary_" + secrets.token_hex(8)},
        {"id": ids[2], "data": marker + "_unicode_" + ("é" * 20)},
        {"id": ids[3], "data": "prefix_" + marker + "_not_at_start"},
    ]
    expected = sorted([ids[0], ids[2]])

    c_source = f'''#include <string.h>
int check_payload(const char *payload, int length) {{
    const char *marker = {json.dumps(marker)};
    size_t actual = strlen(payload);
    size_t marker_len = strlen(marker);
    if (length < 0 || actual != (size_t)length) return 0;
    return actual >= marker_len && strncmp(payload, marker, marker_len) == 0;
}}
'''

    had_output = os.path.isfile(VALID_PAYLOADS_FILE)
    try:
        shutil.copy2(LIBSECCHECK_SO, saved_library)
        shutil.move(PAYLOAD_DIR, saved_payloads)
        if had_output:
            shutil.copy2(VALID_PAYLOADS_FILE, saved_output)

        os.mkdir(PAYLOAD_DIR)
        for index, payload in enumerate(payloads):
            with open(os.path.join(PAYLOAD_DIR, f"case_{index}_{secrets.token_hex(4)}.json"), "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False)

        with open(probe_source, "w", encoding="utf-8") as f:
            f.write(c_source)
        compiled = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", probe_library, probe_source],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=15,
        )
        assert compiled.returncode == 0, "Verifier could not compile its probe library:\n" + compiled.stdout
        os.replace(probe_library, LIBSECCHECK_SO)
        _remove_path(VALID_PAYLOADS_FILE)

        run = subprocess.run(
            [sys.executable, DEPLOY_PREP_PY],
            cwd=WORKSPACE_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=15,
        )
        assert run.returncode == 0, "deploy_prep.py failed when executed:\n" + run.stdout
        assert os.path.isfile(VALID_PAYLOADS_FILE), "deploy_prep.py did not generate valid_payloads.json."
        with open(VALID_PAYLOADS_FILE, "r", encoding="utf-8") as f:
            generated = json.load(f)
        assert generated == expected, \
            f"deploy_prep.py did not use the loaded C function with UTF-8 byte lengths and sorted output; expected {expected}, got {generated}."
    finally:
        _remove_path(LIBSECCHECK_SO)
        if os.path.exists(saved_library):
            shutil.move(saved_library, LIBSECCHECK_SO)
        _remove_path(PAYLOAD_DIR)
        if os.path.exists(saved_payloads):
            shutil.move(saved_payloads, PAYLOAD_DIR)
        _remove_path(VALID_PAYLOADS_FILE)
        if had_output and os.path.exists(saved_output):
            shutil.move(saved_output, VALID_PAYLOADS_FILE)
        shutil.rmtree(temp_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
