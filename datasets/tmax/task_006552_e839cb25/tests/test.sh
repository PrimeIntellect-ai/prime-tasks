#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import shutil
import secrets
import subprocess
import pytest

def test_resource_compiler_exists_and_executable():
    path = "/home/user/resource_compiler.sh"
    assert os.path.exists(path), f"The script {path} does not exist."
    st = os.stat(path)
    assert stat.S_ISREG(st.st_mode), f"The script {path} is not a regular file."
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {path} is not executable."

def test_res_map_generated_correctly():
    path = "/home/user/build/res_map.sh"
    assert os.path.exists(path), f"The file {path} was not generated."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        'export APP_NAME="MyApp"',
        'export ENABLE_LOGS="true"',
        'export API_ENDPOINT="https://api.example.com"',
        'export USER_ONBOARDING="false"'
    ]

    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {path}."

def test_test_res_exists_and_executable():
    path = "/home/user/tests/test_res.sh"
    assert os.path.exists(path), f"The test stub {path} was not generated."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The test stub {path} is not executable."

    with open(path, "r") as f:
        content = f.read()

    assert "#!/bin/bash" in content, f"Shebang missing in {path}."
    assert "source /home/user/build/res_map.sh" in content, f"Source command missing in {path}."

def test_test_results_log_generated_correctly():
    path = "/home/user/build/test_results.log"
    assert os.path.exists(path), f"The log file {path} was not generated."

    with open(path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "PASS: APP_NAME",
        "PASS: ENABLE_LOGS",
        "PASS: API_ENDPOINT",
        "PASS: USER_ONBOARDING"
    ]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {path}, got {len(content)}."
    for i, expected in enumerate(expected_lines):
        assert content[i].strip() == expected, f"Expected line {i+1} to be '{expected}', got '{content[i].strip()}'."

def test_compiler_and_generated_tests_handle_runtime_manifest():
    compiler = "/home/user/resource_compiler.sh"
    manifest = "/home/user/raw_resources.txt"
    res_map = "/home/user/build/res_map.sh"
    test_stub = "/home/user/tests/test_res.sh"
    results_log = "/home/user/build/test_results.log"

    token = secrets.token_hex(8).upper()
    resources = [
        ("STR", f"VERIFY_NAME_{token}", f"RuntimeName{token}"),
        ("BOOL", f"VERIFY_FLAG_{token}", "true"),
        ("STR", f"VERIFY_HOST_{token}", f"service-{token.lower()}.example.test"),
        ("BOOL", f"VERIFY_SWITCH_{token}", "false"),
        ("STR", f"VERIFY_BUILD_{token}", f"build_{token}_73"),
    ]

    with open(manifest, "w") as f:
        for resource_type, key, value in resources:
            f.write(f"{resource_type}:{key.encode().hex()}:{value.encode().hex()}\n")

    shutil.rmtree("/home/user/build", ignore_errors=True)
    shutil.rmtree("/home/user/tests", ignore_errors=True)

    run = subprocess.run(
        [compiler], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert run.returncode == 0, (
        f"Compiler failed on a runtime manifest with exit code {run.returncode}: "
        f"stdout={run.stdout!r}, stderr={run.stderr!r}"
    )

    assert os.path.isfile(res_map), "Compiler did not regenerate res_map.sh."
    assert os.path.isfile(test_stub), "Compiler did not regenerate test_res.sh."
    assert os.access(test_stub, os.X_OK), "Regenerated test_res.sh is not executable."
    assert os.path.isfile(results_log), "Compiler did not create test_results.log."

    with open(res_map) as f:
        map_content = f.read()
    for _, key, value in resources:
        expected_export = f'export {key}="{value}"'
        assert expected_export in map_content, f"Missing decoded export: {expected_export}"

    for _, key, value in resources:
        sourced = subprocess.run(
            ["/bin/bash", "-c", f'source "{res_map}" && printf "%s" "${{{key}}}"'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert sourced.returncode == 0, f"Generated configuration cannot be sourced: {sourced.stderr}"
        assert sourced.stdout == value, f"Generated variable {key} has the wrong value."

    expected_passes = [f"PASS: {key}" for _, key, _ in resources]
    with open(results_log) as f:
        logged = f.read().strip().splitlines()
    assert logged == expected_passes, "Compiler did not execute the generated tests for every runtime resource."

    stub_run = subprocess.run(
        [test_stub], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert stub_run.returncode == 0, f"Generated test stub failed: {stub_run.stderr}"
    assert stub_run.stdout.strip().splitlines() == expected_passes

    correct_map = "".join(f'export {key}="{value}"\n' for _, key, value in resources)
    for failed_index, (_, failed_key, _) in enumerate(resources):
        altered = []
        for index, (_, key, value) in enumerate(resources):
            selected_value = f"WRONG_{token}_{index}" if index == failed_index else value
            altered.append(f'export {key}="{selected_value}"\n')
        with open(res_map, "w") as f:
            f.writelines(altered)

        failed_run = subprocess.run(
            [test_stub], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        assert failed_run.returncode == 0, f"Generated test stub errored while checking {failed_key}."
        expected = [
            (f"FAIL: {key}" if index == failed_index else f"PASS: {key}")
            for index, (_, key, _) in enumerate(resources)
        ]
        assert failed_run.stdout.strip().splitlines() == expected, (
            f"Generated test stub does not independently check resource {failed_key}."
        )

    with open(res_map, "w") as f:
        f.write(correct_map)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
