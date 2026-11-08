#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import math
import shutil
import stat
import subprocess
import tempfile
import pytest

BACKEND_DIR = '/home/user/api_backend'
SOURCE = os.path.join(BACKEND_DIR, 'process_data.c')
BINARY = os.path.join(BACKEND_DIR, 'process_data')
PATCH = os.path.join(BACKEND_DIR, 'fix.patch')
SCRIPT = '/home/user/test_integration.sh'
INPUT = '/home/user/input_data.txt'
REPORT = '/home/user/integration_report.json'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def expected(values):
    return sum(abs(x) for x in values), math.sqrt(sum(x * x for x in values))


def read_report(check_format=False):
    assert os.path.isfile(REPORT), f"Report file {REPORT} is missing."
    raw = open(REPORT, 'r').read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"{REPORT} is not valid JSON.")
    assert "l2_norm_from_api" in data, "Key 'l2_norm_from_api' missing from report."
    assert "l1_norm_from_bash" in data, "Key 'l1_norm_from_bash' missing from report."
    if check_format:
        assert set(data) == {'l2_norm_from_api', 'l1_norm_from_bash'}, "Report has the wrong schema."
        for key in data:
            pattern = r'"' + re.escape(key) + r'"\s*:\s*-?\d+\.\d{4}(?=\s*[,}])'
            assert re.search(pattern, raw), f"{key} is not formatted to exactly 4 decimal places as a JSON number."
    return data


def write_input(values):
    with open(INPUT, 'w') as f:
        for value in values:
            f.write(f'{value}\n')


def invoke_script():
    result = run([SCRIPT], cwd='/home/user', timeout=20)
    assert result.returncode == 0, f"Integration script failed:\n{result.stdout}\n{result.stderr}"


def valgrind(binary, payload):
    return run([
        'valgrind', '--leak-check=full',
        '--show-leak-kinds=definite,indirect,possible',
        '--errors-for-leak-kinds=definite,indirect,possible',
        '--error-exitcode=99', binary
    ], input=payload, timeout=20)


def test_fix_patch_exists_and_contains_free():
    patch_path = PATCH
    assert os.path.isfile(patch_path), f"Patch file {patch_path} is missing."
    with open(patch_path, 'r') as f:
        content = f.read()
    assert "free" in content, "The patch file does not appear to add a free() call."
    assert "+" in content and "-" in content, "The patch file does not look like a unified diff."
    assert re.search(r'^--- ', content, re.M) and re.search(r'^\+\+\+ ', content, re.M)
    assert re.search(r'^@@ ', content, re.M), "Patch lacks a unified-diff hunk."


def test_patch_applies_and_represents_the_leak_fix():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with tempfile.TemporaryDirectory() as td:
        fixed_copy = os.path.join(td, 'process_data.c')
        original_copy = os.path.join(td, 'original.c')
        shutil.copy2(SOURCE, fixed_copy)

        reverse = run(['patch', '--batch', '-R', fixed_copy, PATCH])
        assert reverse.returncode == 0, f"fix.patch cannot be reverse-applied to the submitted fixed source:\n{reverse.stdout}\n{reverse.stderr}"
        os.rename(fixed_copy, original_copy)

        forward_copy = os.path.join(td, 'process_data.c')
        shutil.copy2(original_copy, forward_copy)
        forward = run(['patch', '--batch', forward_copy, PATCH])
        assert forward.returncode == 0, f"fix.patch cannot be applied to the reconstructed original:\n{forward.stdout}\n{forward.stderr}"
        assert open(forward_copy, 'rb').read() == open(SOURCE, 'rb').read(), "Patch does not recreate the submitted fixed source."

        old_binary = os.path.join(td, 'old_process_data')
        compiled = run(['gcc', '-g', '-O0', original_copy, '-lm', '-o', old_binary])
        assert compiled.returncode == 0, f"Reconstructed original source does not compile:\n{compiled.stderr}"
        vg = valgrind(old_binary, '{"data": [1, 2, 3, 4]}\n')
        summary = vg.stdout + vg.stderr
        match = re.search(r'definitely lost:\s*([0-9,]+) bytes', summary)
        assert match and int(match.group(1).replace(',', '')) > 0, "Patch does not reconstruct the original memory leak."


def test_process_data_binary_exists_and_executable():
    bin_path = BINARY
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"Compiled binary {bin_path} is not executable."
    with open(bin_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "process_data is not a compiled ELF binary."
    debug = run(['readelf', '-S', bin_path])
    assert debug.returncode == 0 and '.debug_info' in debug.stdout, "process_data was not compiled with debugging symbols."


def test_fixed_source_compiles_and_binary_is_correct_and_leak_free():
    values = [-12.75, 0.125, 3.5, -4.25, 8.0, 1.0, -2.0, 6.25,
              9.5, -0.75, 2.25, 5.5, -7.125, 11.0, -1.5]
    payload = json.dumps({'data': values}) + '\n'
    result = run([BINARY], input=payload, timeout=10)
    assert result.returncode == 0, f"Backend failed:\n{result.stderr}"
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Backend did not return JSON: {result.stdout!r}")
    assert set(output) == {'norm'}
    assert math.isclose(float(output['norm']), expected(values)[1], abs_tol=0.00011)

    vg = valgrind(BINARY, payload)
    assert vg.returncode == 0, f"Valgrind found memory errors or leaks:\n{vg.stderr}"
    assert re.search(r'definitely lost:\s*0 bytes', vg.stdout + vg.stderr), "Backend still definitely leaks memory."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'process_data')
        compiled = run(['gcc', '-g', '-O0', SOURCE, '-lm', '-o', rebuilt])
        assert compiled.returncode == 0, f"Fixed source does not compile:\n{compiled.stderr}"
        vg2 = valgrind(rebuilt, payload)
        assert vg2.returncode == 0, f"Compiled submitted source has memory errors or leaks:\n{vg2.stderr}"


def test_integration_script_exists_and_executable():
    script_path = SCRIPT
    assert os.path.isfile(script_path), f"Integration script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Integration script {script_path} is not executable."


def test_integration_report_json():
    data = read_report()
    l2_norm = float(data["l2_norm_from_api"])
    l1_norm = float(data["l1_norm_from_bash"])
    input_path = INPUT
    assert os.path.isfile(input_path), f"Input file {input_path} is missing."
    with open(input_path, 'r') as f:
        numbers = [float(line.strip()) for line in f if line.strip()]
    expected_l1, expected_l2 = expected(numbers)
    assert math.isclose(l1_norm, expected_l1, rel_tol=1e-3), f"Expected L1 norm ~{expected_l1:.4f}, got {l1_norm}"
    assert math.isclose(l2_norm, expected_l2, rel_tol=1e-3), f"Expected L2 norm ~{expected_l2:.4f}, got {l2_norm}"


def test_script_serializes_calls_api_deserializes_and_handles_new_inputs():
    original_input = open(INPUT, 'rb').read() if os.path.exists(INPUT) else None
    backup_binary = BINARY + '.verifier-backup'
    capture = '/tmp/verifier_backend_stdin.json'
    values = [-2.125, 4.75, -9.5, 0.0625, 13.25, -1.0]
    sentinel = 123.4567
    try:
        if os.path.exists(capture):
            os.unlink(capture)
        os.rename(BINARY, backup_binary)
        with open(BINARY, 'w') as f:
            f.write('#!/bin/sh\ncat > ' + capture + "\nprintf '{\\\"norm\\\": 123.4567}\\n'\n")
        os.chmod(BINARY, 0o755)
        write_input(values)
        if os.path.exists(REPORT):
            os.unlink(REPORT)
        invoke_script()
        assert os.path.isfile(capture), "Integration script did not invoke the compiled backend path."
        try:
            request = json.load(open(capture))
        except Exception as exc:
            pytest.fail(f"Script did not send valid JSON to the backend: {exc}")
        assert set(request) == {'data'}, "Serialized API request has the wrong schema."
        assert len(request['data']) == len(values)
        assert all(math.isclose(float(a), b, abs_tol=1e-12) for a, b in zip(request['data'], values)), "Serialized API request did not contain the input numbers."
        report = read_report(check_format=True)
        assert math.isclose(float(report['l2_norm_from_api']), sentinel, abs_tol=0.00001), "Script did not extract the norm returned by the API."
        assert math.isclose(float(report['l1_norm_from_bash']), expected(values)[0], abs_tol=0.00011), "Script did not calculate the Bash-native L1 norm."
    finally:
        if os.path.exists(BINARY):
            os.unlink(BINARY)
        if os.path.exists(backup_binary):
            os.rename(backup_binary, BINARY)
        if original_input is not None:
            with open(INPUT, 'wb') as f:
                f.write(original_input)

    values2 = [0.3333, -7.7777, 15.125, -0.5, 2.0, -3.25, 6.625]
    write_input(values2)
    invoke_script()
    report = read_report(check_format=True)
    l1, l2 = expected(values2)
    assert math.isclose(float(report['l1_norm_from_bash']), l1, abs_tol=0.00011)
    assert math.isclose(float(report['l2_norm_from_api']), l2, abs_tol=0.00011)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
