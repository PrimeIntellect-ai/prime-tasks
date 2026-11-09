#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import subprocess


def test_script_exists():
    script_path = "/home/user/get_latest_prod.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_output_file_exists():
    output_path = "/home/user/latest_versions.log"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."


def test_output_file_contents():
    output_path = "/home/user/latest_versions.log"
    expected_lines = [
        "AnalyticsModule:2.0.0-beta",
        "ChatApp:1.0.0",
        "PaymentApp:1.3.2"
    ]

    with open(output_path, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {output_path} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_script_processes_build_data():
    script_path = "/home/user/get_latest_prod.sh"
    input_path = "/home/user/build_data.b64"
    output_path = "/home/user/latest_versions.log"

    with open(input_path, "rb") as f:
        original_input = f.read()
    with open(output_path, "rb") as f:
        original_output = f.read()

    token = secrets.token_hex(5)
    alpha = f"Alpha{token}"
    beta = f"Beta{token}"
    gamma = f"Gamma{token}"
    ignored = f"Ignored{token}"
    major = secrets.randbelow(20) + 2

    records = [
        f"{alpha},{major}.9.9,production",
        f"{alpha},{major}.10.0,production",
        f"{alpha},{major + 1}.0.0-rc1,production",
        f"{alpha},{major + 1}.0.0,production",
        f"{alpha},99.0.0,staging",
        f"{alpha},100.0.0,Production",
        f"{beta},1.2.0-rc1,production",
        f"{beta},1.2.0,production",
        f"{beta},8.0.0,development",
        f"{gamma},0.9.9,production",
        f"{gamma},0.10.0,production",
        f"{ignored},50.0.0,staging",
    ]
    secrets.SystemRandom().shuffle(records)
    encoded = b"\n".join(base64.b64encode(r.encode()) for r in records) + b"\n"

    expected_lines = sorted([
        f"{alpha}:{major + 1}.0.0",
        f"{beta}:1.2.0",
        f"{gamma}:0.10.0",
    ])

    try:
        with open(input_path, "wb") as f:
            f.write(encoded)
        if os.path.exists(output_path):
            os.remove(output_path)

        result = subprocess.run(
            ["bash", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"The script failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(output_path), "The script did not generate latest_versions.log."

        with open(output_path, "r") as f:
            content = f.read().strip()
        actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
        assert actual_lines == expected_lines, (
            "The script did not correctly decode, filter, semantically compare, and sort "
            f"the generated records.\nExpected:\n{chr(10).join(expected_lines)}\n"
            f"Actual:\n{chr(10).join(actual_lines)}"
        )
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        with open(output_path, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
