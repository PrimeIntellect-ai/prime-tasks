#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess


def test_fixed_binary_success_rate():
    binary_path = "/home/user/telemetry_parser_fixed"
    assert os.path.isfile(binary_path), f"Fixed binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Fixed binary is not executable at {binary_path}"

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Fixed service must be a compiled ELF executable"

    deployed_path = "/app/telemetry_parser"
    if os.path.isfile(deployed_path):
        with open(binary_path, "rb") as fixed, open(deployed_path, "rb") as deployed:
            assert fixed.read() != deployed.read(), "Fixed binary is identical to the vulnerable deployed binary"

    nonce = secrets.token_hex(12)
    inputs = []
    debug_cases = {}
    required_benign = set()

    # Exercise exactly 1000 independently generated inputs: benign DEBUG logs,
    # benign non-DEBUG logs, and oversized DEBUG logs.
    for i in range(1000):
        value = float(i * i)
        if i % 10 == 0:
            msg = f"Oversized_{nonce}_{i}_" + (secrets.choice("ABCDEFGH") * (200 + secrets.randbelow(251)))
            inputs.append(f"[DEBUG] {msg} {value}\n")
            debug_cases[i] = (msg, True)
        elif i % 10 == 1:
            inputs.append(f"[INFO] Info_{nonce}_{i} {value}\n")
        else:
            # Retain the original verifier's specific benign assertion while
            # making every other expected message unpredictable.
            msg = "BenignMessage4" if i == 4 else f"Benign_{nonce}_{i}_{secrets.token_hex(4)}"
            inputs.append(f"[DEBUG] {msg} {value}\n")
            debug_cases[i] = (msg, False)
            required_benign.add(i)

    process = subprocess.run(
        [binary_path],
        input="".join(inputs),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )

    crashed = process.returncode != 0
    success_rate = 0.0 if crashed else 1.0
    assert success_rate >= 1.0, (
        f"Expected success_rate >= 1.0, got {success_rate}. "
        f"The binary crashed or returned non-zero exit code: {process.returncode}."
    )

    output_lines = [line for line in process.stdout.splitlines() if line.strip()]
    seen = set()
    previous_index = -1
    found_benign = False

    for line in output_lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"Service emitted invalid JSON: {line!r}") from exc

        assert isinstance(data, dict), f"Output is not a JSON object: {line!r}"
        assert set(data) == {"level", "msg", "val"}, f"Unexpected output format: {data!r}"
        assert data["level"] == "DEBUG", f"Unexpected output level: {data!r}"
        assert isinstance(data["msg"], str), f"Output message is not a string: {data!r}"
        assert isinstance(data["val"], (int, float)) and not isinstance(data["val"], bool), (
            f"Output value is not numeric: {data!r}"
        )
        assert math.isfinite(float(data["val"])), f"Output value is not finite: {data!r}"

        index = int(round(float(data["val"])))
        assert index in debug_cases and math.isclose(float(data["val"]), float(index), abs_tol=1e-6), (
            f"Output does not correspond to any DEBUG input: {data!r}"
        )
        assert index > previous_index, "Outputs are duplicated or not in input order"
        assert index not in seen, "Duplicate output for one input"

        expected_msg, oversized = debug_cases[index]
        if oversized:
            # Oversized records may be ignored entirely. If emitted, their
            # message may be safely truncated, but must remain valid JSON and
            # correspond to the original record.
            assert data["msg"] and expected_msg.startswith(data["msg"]), (
                f"Incorrect oversized-message output: {data!r}"
            )
        else:
            assert data["msg"] == expected_msg, f"Incorrect benign output: {data!r}"

        if index == 4 and data["msg"] == "BenignMessage4":
            assert math.isclose(float(data["val"]), 4.0, abs_tol=1e-6), "Square root calculation is incorrect"
            found_benign = True

        seen.add(index)
        previous_index = index

    missing = required_benign - seen
    assert not missing, f"The service omitted {len(missing)} benign DEBUG outputs"
    assert found_benign, "The patched binary did not correctly output JSON for benign inputs."


if __name__ == "__main__":
    test_fixed_binary_success_rate()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
