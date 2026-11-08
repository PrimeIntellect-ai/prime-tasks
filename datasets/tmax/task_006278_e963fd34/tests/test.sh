#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile

AUDIT_PATH = '/home/user/audit.py'
LOG_PATH = '/home/user/vulnerabilities.log'
BINARIES_PATH = '/home/user/binaries'


def run_audit():
    return subprocess.run(
        ['python3', AUDIT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def test_vulnerabilities_log_exists():
    assert os.path.exists(LOG_PATH), f"The output file {LOG_PATH} does not exist."
    assert os.path.isfile(LOG_PATH), f"The path {LOG_PATH} is not a file."


def test_vulnerabilities_log_content():
    with open(LOG_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {LOG_PATH} does not contain valid JSON."

    expected_data = {
        "bin2": "audit_bypass_99",
        "bin4": "root_access_x"
    }

    assert isinstance(data, dict), "The JSON root must be an object (dictionary)."
    assert data == expected_data, (
        f"The contents of {LOG_PATH} do not match the expected output.\n"
        f"Expected: {expected_data}\n"
        f"Actual: {data}"
    )


def test_audit_script_scans_and_extracts_dynamic_elf_files():
    assert os.path.exists(AUDIT_PATH), f"The required script {AUDIT_PATH} does not exist."
    assert os.path.isfile(AUDIT_PATH), f"The path {AUDIT_PATH} is not a regular file."

    workspace = tempfile.mkdtemp(prefix='audit-verifier-')
    saved_binaries = os.path.join(workspace, 'original-binaries')
    os.rename(BINARIES_PATH, saved_binaries)
    os.mkdir(BINARIES_PATH)

    token = secrets.token_hex(8)
    cases = [
        ('vuln_a_' + token, 'dynamic_alpha_' + token, ['-fno-pie', '-no-pie', '-Wl,-z,execstack'], True),
        ('vuln_b_' + token, 'dynamic_beta_' + token, ['-fno-pie', '-no-pie', '-Wl,-z,execstack'], True),
        ('nonpie_nx_' + token, 'must_not_appear_1_' + token, ['-fno-pie', '-no-pie', '-Wl,-z,noexecstack'], False),
        ('pie_exec_' + token, 'must_not_appear_2_' + token, ['-fPIE', '-pie', '-Wl,-z,execstack'], False),
        ('pie_nx_' + token, 'must_not_appear_3_' + token, ['-fPIE', '-pie', '-Wl,-z,noexecstack'], False),
    ]
    expected = {}

    try:
        for name, plaintext, flags, vulnerable in cases:
            encoded = bytes(b ^ 0x42 for b in plaintext.encode('ascii')).hex()
            source = os.path.join(workspace, name + '.c')
            output = os.path.join(BINARIES_PATH, name)
            with open(source, 'w') as f:
                f.write(
                    'const char secret[] __attribute__((section(".secret"))) = '
                    f'"{encoded}";\nint main(void) {{ return 0; }}\n'
                )
            subprocess.run(['gcc', source, '-o', output] + flags, check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if vulnerable:
                expected[name] = plaintext

        if os.path.lexists(LOG_PATH):
            os.remove(LOG_PATH)

        result = run_audit()
        assert result.returncode == 0, (
            f"Executing {AUDIT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(LOG_PATH), f"Executing {AUDIT_PATH} did not create {LOG_PATH}."

        with open(LOG_PATH, 'r') as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError as exc:
                assert False, f"The dynamically generated log is not valid JSON: {exc}"

        assert isinstance(actual, dict), "The dynamically generated JSON root must be an object."
        assert actual == expected, (
            "audit.py did not correctly identify and decode dynamically generated ELF files.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
    finally:
        shutil.rmtree(BINARIES_PATH, ignore_errors=True)
        os.rename(saved_binaries, BINARIES_PATH)
        shutil.rmtree(workspace, ignore_errors=True)
        # Re-run the submitted artifact on the original inputs so the required final
        # output remains present and is checked below as well.
        if os.path.isfile(AUDIT_PATH):
            try:
                run_audit()
            except subprocess.TimeoutExpired:
                pass


def test_original_inputs_after_execution():
    assert os.path.isfile(LOG_PATH), f"The output file {LOG_PATH} does not exist after execution."
    with open(LOG_PATH, 'r') as f:
        data = json.load(f)
    expected_data = {
        "bin2": "audit_bypass_99",
        "bin4": "root_access_x"
    }
    assert isinstance(data, dict), "The JSON root must be an object (dictionary)."
    assert data == expected_data, (
        f"The contents of {LOG_PATH} do not match the expected output after executing audit.py.\n"
        f"Expected: {expected_data}\nActual: {data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
