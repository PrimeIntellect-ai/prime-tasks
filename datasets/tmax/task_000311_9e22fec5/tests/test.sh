#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

PROJECT = '/home/user/project'


def test_build_success_log():
    log_path = '/home/user/project/build_success.log'
    assert os.path.isfile(log_path), f"The file {log_path} does not exist. Did you redirect the output of build.sh?"

    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert content == "BUILD SUCCESSFUL", f"Expected '{log_path}' to contain exactly 'BUILD SUCCESSFUL', but found '{content}'."


def test_cleaned_asset_file():
    asset_path = '/home/user/project/assets/config_data.bin'
    assert os.path.isfile(asset_path), f"The file {asset_path} does not exist."

    with open(asset_path, 'rb') as f:
        content = f.read()

    assert content == b"VALID_ASSET_123", f"Expected '{asset_path}' to contain exactly 'VALID_ASSET_123', but found {content!r}."


def test_threshold_script_is_fixed_and_behaves_correctly():
    script_path = os.path.join(PROJECT, 'calculate_threshold.sh')
    weights_path = os.path.join(PROJECT, 'weights.txt')

    assert os.path.isfile(script_path), f"The file {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The file {script_path} is not executable."

    with open(script_path, 'r', encoding='utf-8') as f:
        script = f.read()

    assert 'awk' in script, "calculate_threshold.sh no longer uses the required awk calculation."
    assert re.search(r'(?:printf|sprintf)\s*(?:\(\s*)?[\"\'][%][-+ #0]*\.1f', script), \
        "The awk calculation must format the sum to exactly one decimal place."

    with open(weights_path, 'rb') as f:
        original_weights = f.read()

    try:
        # Default awk formatting prints this as 0.300001, while correct
        # one-decimal rounding produces the required string 0.3.
        with open(weights_path, 'wb') as f:
            f.write(b'0.300001\n')
        result = subprocess.run([script_path], cwd=PROJECT, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, (
            "calculate_threshold.sh did not round an awk sum to one decimal place: "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
    finally:
        with open(weights_path, 'wb') as f:
            f.write(original_weights)


def test_real_build_script_executes_and_validates_inputs():
    build_path = os.path.join(PROJECT, 'build.sh')
    asset_path = os.path.join(PROJECT, 'assets', 'config_data.bin')
    weights_path = os.path.join(PROJECT, 'weights.txt')

    assert os.path.isfile(build_path), f"The file {build_path} does not exist."
    assert os.access(build_path, os.X_OK), f"The file {build_path} is not executable."

    successful = subprocess.run([build_path], cwd=PROJECT, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert successful.returncode == 0, (
        f"build.sh failed: stdout={successful.stdout!r}, stderr={successful.stderr!r}"
    )
    assert successful.stdout.strip() == 'BUILD SUCCESSFUL', (
        f"Expected build.sh to print exactly 'BUILD SUCCESSFUL', got {successful.stdout.strip()!r}."
    )

    with open(asset_path, 'rb') as f:
        original_asset = f.read()
    try:
        with open(asset_path, 'wb') as f:
            f.write(b'INVALID_ASSET')
        bad_asset = subprocess.run([build_path], cwd=PROJECT, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert bad_asset.returncode != 0, "build.sh did not reject a corrupted asset."
    finally:
        with open(asset_path, 'wb') as f:
            f.write(original_asset)

    with open(weights_path, 'rb') as f:
        original_weights = f.read()
    try:
        with open(weights_path, 'wb') as f:
            f.write(b'0.4\n')
        bad_threshold = subprocess.run([build_path], cwd=PROJECT, text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert bad_threshold.returncode != 0, "build.sh did not run and enforce calculate_threshold.sh."
    finally:
        with open(weights_path, 'wb') as f:
            f.write(original_weights)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
