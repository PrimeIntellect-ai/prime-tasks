#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess


def read_resolution(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip()


def run_solver(solve_script_path, resolution_path, expected):
    if os.path.exists(resolution_path):
        os.remove(resolution_path)

    result = subprocess.run(
        ["python3", solve_script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"solve.py exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(resolution_path), (
        f"File missing after executing solve.py: {resolution_path}. "
        "The script must write the result here."
    )
    content = read_resolution(resolution_path)
    assert content == expected, (
        f"Incorrect value in {resolution_path}. "
        f"Expected '{expected}', but got '{content}'."
    )


def test_final_state():
    solve_script_path = "/home/user/solve.py"
    resolution_path = "/home/user/resolution.txt"
    dump_path = "/home/user/crash.dmp"

    # Preserve the original verifier's assertions.
    assert os.path.isfile(solve_script_path), f"File missing: {solve_script_path}. You must write the solution script here."
    assert os.path.isfile(resolution_path), f"File missing: {resolution_path}. The script must output the result here."

    content = read_resolution(resolution_path)
    expected_value = "7.62079e-17"
    assert content == expected_value, (
        f"Incorrect value in {resolution_path}. "
        f"Expected '{expected_value}', but got '{content}'."
    )

    with open(dump_path, "rb") as f:
        original_dump = f.read()

    try:
        # Execute the submitted artifact against the supplied dump.
        run_solver(solve_script_path, resolution_path, expected_value)

        # Exercise dynamic dump parsing and the cancellation-safe formula on
        # unpredictable small inputs rather than trusting a fabricated constant.
        for exponent in (8, 10, 12):
            coefficient = 10_000_000 + secrets.randbelow(90_000_000)
            x = coefficient * (10.0 ** (-(exponent + 7)))
            expected = format(2.0 * math.sin(x / 2.0) ** 2, ".5e")
            payload = json.dumps({"x": x}, separators=(",", ":"))
            prefix = secrets.token_hex(512)
            suffix = secrets.token_hex(512)
            synthetic_dump = (
                prefix + "\n[TICKET-9921-DATA] " + payload + "\n" + suffix + "\n"
            ).encode("ascii")

            with open(dump_path, "wb") as f:
                f.write(synthetic_dump)

            run_solver(solve_script_path, resolution_path, expected)
    finally:
        with open(dump_path, "wb") as f:
            f.write(original_dump)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
