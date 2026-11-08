#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import math
import os
import re
import secrets
import shutil
import subprocess
import sysconfig

import pytest

BUNDLE = '/home/user/support_bundle'
EXT_DIR = os.path.join(BUNDLE, 'ext')


def test_diagnostic_report_exists_and_correct():
    report_path = '/home/user/diagnostic_report.json'
    assert os.path.isfile(report_path), f"Diagnostic report missing at {report_path}"

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert "missing_linker_library" in report, "Key 'missing_linker_library' missing in diagnostic report."
    assert report["missing_linker_library"] == "m", "Incorrect missing linker library identified."

    assert "corrected_total_sum" in report, "Key 'corrected_total_sum' missing in diagnostic report."
    assert float(report["corrected_total_sum"]) == 2.0, "Incorrect corrected total sum in diagnostic report."

    assert "first_failing_transaction_id" in report, "Key 'first_failing_transaction_id' missing in diagnostic report."
    assert report["first_failing_transaction_id"] == "TXN-102", "Incorrect first failing transaction ID identified."


def test_setup_was_fixed_and_extension_builds():
    setup_path = os.path.join(EXT_DIR, 'setup.py')
    assert os.path.isfile(setup_path), f"setup.py missing at {setup_path}"

    with open(setup_path, 'r') as f:
        source = f.read()
    tree = ast.parse(source, filename=setup_path)

    library_lists = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'Extension':
            for keyword in node.keywords:
                if keyword.arg == 'libraries':
                    try:
                        library_lists.append(ast.literal_eval(keyword.value))
                    except Exception:
                        pass
    assert any(isinstance(libs, (list, tuple)) and 'm' in libs for libs in library_lists), \
        "The Extension in setup.py does not include 'm' in its libraries list."

    for path in glob.glob(os.path.join(EXT_DIR, 'fast_aggregator*.so')):
        os.remove(path)
    shutil.rmtree(os.path.join(EXT_DIR, 'build'), ignore_errors=True)

    result = subprocess.run(
        ['python3', 'setup.py', 'build_ext', '--inplace'],
        cwd=EXT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"Extension build failed:\n{result.stdout}"

    suffix = sysconfig.get_config_var('EXT_SUFFIX')
    artifacts = glob.glob(os.path.join(EXT_DIR, 'fast_aggregator*' + suffix)) if suffix else []
    assert artifacts, "build_ext --inplace did not produce a Python extension artifact."

    artifact = artifacts[0]
    probe = subprocess.run(
        ['python3', '-c',
         "import importlib.util,sys; p=sys.argv[1]; "
         "s=importlib.util.spec_from_file_location('fast_aggregator',p); "
         "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
         "assert m.fast_sum([1.25,2.75]) == 4.0", artifact],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert probe.returncode == 0, f"Built extension could not be loaded and exercised:\n{probe.stdout}"


def test_build_fix_patch_exists_and_is_a_unified_setup_diff():
    patch_path = os.path.join(BUNDLE, 'build_fix.patch')
    assert os.path.isfile(patch_path), f"Patch file missing at {patch_path}"
    with open(patch_path, 'r') as f:
        content = f.read()
    assert len(content.strip()) > 0, "Patch file is empty."
    assert re.search(r'^---\s+.*setup\.py', content, re.MULTILINE), "Patch lacks a unified-diff source header for setup.py."
    assert re.search(r'^\+\+\+\s+.*setup\.py', content, re.MULTILINE), "Patch lacks a unified-diff destination header for setup.py."
    assert re.search(r'^@@\s', content, re.MULTILINE), "Patch lacks a unified-diff hunk."
    assert re.search(r'^-.*libraries\s*=\s*\[\s*\]', content, re.MULTILINE), \
        "Patch does not remove the empty libraries list."
    assert re.search(r'^\+.*libraries\s*=.*[\"\']m[\"\']', content, re.MULTILINE), \
        "Patch does not add 'm' to the libraries list."


def test_corrected_sum_txt_exists_and_correct():
    sum_path = os.path.join(BUNDLE, 'corrected_sum.txt')
    assert os.path.isfile(sum_path), f"Corrected sum file missing at {sum_path}"

    with open(sum_path, 'r') as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {sum_path} is not a valid number.")

    assert val == 2.0, f"Corrected sum in {sum_path} is incorrect. Expected 2.0, got {val}."


def test_process_data_fallback_handles_unseen_cancellation_input():
    script_path = os.path.join(BUNDLE, 'process_data.py')
    data_path = os.path.join(BUNDLE, 'data.csv')
    assert os.path.isfile(script_path), f"Processing script missing at {script_path}"

    with open(data_path, 'rb') as f:
        original_data = f.read()

    count = 20 + secrets.randbelow(80)
    values = [1.0e16] + [1.0] * count + [-1.0e16, 0.25, 0.5]
    expected = math.fsum(values)

    try:
        with open(data_path, 'w') as f:
            for value in values:
                f.write(repr(value) + '\n')

        result = subprocess.run(
            ['python3', script_path],
            cwd=BUNDLE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
    finally:
        with open(data_path, 'wb') as f:
            f.write(original_data)

    assert result.returncode == 0, f"process_data.py failed on valid input:\n{result.stdout}"
    match = re.search(r'Total:\s*([^\s]+)', result.stdout)
    assert match, f"Could not find the reported total in output:\n{result.stdout}"
    try:
        actual = float(match.group(1))
    except ValueError:
        pytest.fail(f"process_data.py emitted a nonnumeric total: {match.group(1)}")
    assert actual == expected, f"Fallback still loses precision: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
