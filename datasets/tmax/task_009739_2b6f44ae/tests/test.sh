#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile


def test_corrupted_payload_extracted():
    payload_file = "/home/user/corrupted_payload.json"
    assert os.path.exists(payload_file), f"File {payload_file} does not exist."

    with open(payload_file, "r") as f:
        content = f.read()

    # The corrupted payload is exactly '{"amount": 15,'
    assert content == '{"amount": 15,', f"Expected corrupted payload to be exactly '{{\"amount\": 15,', but got {repr(content)}"


def test_summary_result():
    result_file = "/home/user/summary_result.txt"
    assert os.path.exists(result_file), f"File {result_file} does not exist."

    with open(result_file, "r") as f:
        content = f.read().strip()

    assert content == "16777219.00", f"Expected summary result to be '16777219.00', but got '{content}'"


def test_process_tx_fixed():
    script_path = "/home/user/process_tx.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."

    input_data = '{"amount": 1}\n{"bad": \n{"amount": 2}\n'

    result = subprocess.run(
        ["python3", script_path],
        input=input_data,
        text=True,
        capture_output=True
    )

    assert result.returncode == 0, f"process_tx.py exited with error code {result.returncode}. stderr: {result.stderr}"

    stdout_lines = [line.strip() for line in result.stdout.strip().split("\n")]

    assert "Processed: 1" in stdout_lines, "Expected 'Processed: 1' in output."
    assert "Error: Corrupted input" in stdout_lines, "Expected 'Error: Corrupted input' in output."
    assert "Processed: 2" in stdout_lines, "Expected 'Processed: 2' in output."


def test_process_tx_handles_unpredictable_corruption_and_continues():
    script_path = "/home/user/process_tx.py"
    a, b, c = [secrets.randbelow(900000) + 100000 for _ in range(3)]
    malformed_number = secrets.randbelow(900000) + 100000
    token = secrets.token_hex(12)

    lines = [
        json.dumps({"amount": a}),
        '{"amount": ' + str(malformed_number) + ', "items": [1, 2',
        json.dumps({"amount": b}),
        'not-json-' + token,
        json.dumps({"amount": c}),
    ]
    result = subprocess.run(
        ["python3", script_path],
        input="\n".join(lines) + "\n",
        text=True,
        capture_output=True,
        timeout=10,
    )

    assert result.returncode == 0, result.stderr
    assert result.stderr == "", f"Unexpected stderr: {result.stderr!r}"
    assert result.stdout.splitlines() == [
        f"Processed: {a}",
        "Error: Corrupted input",
        f"Processed: {b}",
        "Error: Corrupted input",
        f"Processed: {c}",
    ]


def run_summarizer(binary, cwd):
    result = subprocess.run(
        [binary], cwd=cwd, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, f"{binary} failed: {result.stderr}"
    assert result.stderr == "", f"{binary} wrote unexpected stderr: {result.stderr!r}"
    return result.stdout


def test_summarize_source_binary_and_saved_output():
    source = "/home/user/summarize.c"
    binary = "/home/user/summarize"
    result_file = "/home/user/summary_result.txt"

    assert os.path.isfile(source), f"Source {source} does not exist."
    assert os.path.isfile(binary), f"Binary {binary} does not exist."
    assert os.access(binary, os.X_OK), f"Binary {binary} is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "summarize is not a compiled ELF executable."
    assert os.stat(binary).st_mtime_ns >= os.stat(source).st_mtime_ns, \
        "summarize was not recompiled after summarize.c was modified."

    with tempfile.TemporaryDirectory() as build_dir:
        rebuilt = os.path.join(build_dir, "summarize-from-source")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", source, "-o", rebuilt],
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, \
            f"summarize.c does not compile: {compile_result.stderr}"

        # Odd integers above 2^24 cannot be represented exactly by float. The
        # values are chosen at verification time so fixed-output programs fail.
        for _ in range(3):
            case_dir = tempfile.mkdtemp(dir=build_dir)
            base = (secrets.randbelow(70000000) + 20000001) | 1
            additions = secrets.randbelow(20) + 3
            values = [base] + [1] * additions
            with open(os.path.join(case_dir, "amounts.csv"), "w") as f:
                f.write("\n".join(f"{value}.00" for value in values) + "\n")

            expected = f"{sum(values):.2f}\n"
            rebuilt_output = run_summarizer(rebuilt, case_dir)
            installed_output = run_summarizer(binary, case_dir)
            assert rebuilt_output == expected, \
                f"summarize.c still loses precision: expected {expected!r}, got {rebuilt_output!r}"
            assert installed_output == expected, \
                f"Installed summarize is stale or incorrect: expected {expected!r}, got {installed_output!r}"

    actual_output = run_summarizer(binary, "/home/user")
    with open(result_file, "r") as f:
        saved_output = f.read()
    assert saved_output == actual_output, \
        "summary_result.txt is not the standard output of the compiled summarize binary."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
