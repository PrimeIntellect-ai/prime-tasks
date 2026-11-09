#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_UP

import pytest

ETL = "/home/user/etl.sh"
TEST_ETL = "/home/user/test_etl.sh"
RAW = "/home/user/raw_events.csv"
SUMMARY = "/home/user/summary.csv"


def run_script(args, timeout=15):
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=env)


def expected_output(records):
    totals = {}
    counts = {}
    for tags, value in records:
        if value is None:
            continue
        for tag in tags:
            totals[tag] = totals.get(tag, 0) + value
            counts[tag] = counts.get(tag, 0) + 1

    lines = ["Token,Sum,ValidCount,Mean"]
    for tag in sorted(totals):
        mean = (Decimal(totals[tag]) / Decimal(counts[tag])).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        )
        lines.append(f"{tag},{totals[tag]},{counts[tag]},{mean:.2f}")
    return "\n".join(lines)


def make_random_case(directory, case_number):
    while True:
        nonce = secrets.token_hex(6)
        tags = [f"tag_{nonce}_{letter}" for letter in "abcdef"]
        records = []

        # Guarantee every token has valid data, including a valid zero.
        for index, tag in enumerate(tags):
            records.append(([tag], 0 if index == 0 else random.randint(-25, 35)))

        for _ in range(random.randint(18, 28)):
            selected = random.sample(tags, random.randint(1, 4))
            value = None if random.random() < 0.30 else random.randint(-40, 50)
            records.append((selected, value))

        random.shuffle(records)

        # Avoid exact half-way decimal cases, where implementations of
        # floating-point printf can legitimately differ at the last digit.
        totals = {}
        counts = {}
        for selected, value in records:
            if value is None:
                continue
            for tag in selected:
                totals[tag] = totals.get(tag, 0) + value
                counts[tag] = counts.get(tag, 0) + 1
        if all((abs(totals[t]) * 100 % counts[t]) * 2 != counts[t] for t in totals):
            break

    input_path = os.path.join(directory, f"input_{case_number}.csv")
    output_path = os.path.join(directory, f"output_{case_number}.csv")
    with open(input_path, "w", newline="") as handle:
        handle.write("ID,Tags,Value\n")
        for row_id, (selected, value) in enumerate(records, 1):
            value_field = "" if value is None else str(value)
            handle.write(f"{row_id},{'|'.join(selected)},{value_field}\n")

    return input_path, output_path, records


def test_etl_script_exists_and_executable():
    script_path = ETL
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_test_etl_script_exists_and_executable():
    script_path = TEST_ETL
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_etl_script_execution_and_output():
    input_file = RAW
    output_file = SUMMARY
    script_path = ETL

    if os.path.exists(output_file):
        os.remove(output_file)

    result = run_script(["bash", script_path, input_file, output_file])
    assert result.returncode == 0, f"The script {script_path} failed with return code {result.returncode}.\nStderr: {result.stderr}"
    assert os.path.exists(output_file), f"The script did not create the output file at {output_file}."

    expected = """Token,Sum,ValidCount,Mean
alpha,35,3,11.67
beta,25,2,12.50
delta,20,2,10.00
gamma,15,1,15.00"""
    with open(output_file, "r") as handle:
        content = handle.read().strip()
    assert content == expected, f"The content of {output_file} does not match the expected output.\nExpected:\n{expected}\n\nGot:\n{content}"


def test_etl_on_unpredictable_inputs():
    with tempfile.TemporaryDirectory(prefix="etl-verifier-") as directory:
        for case_number in range(4):
            input_path, output_path, records = make_random_case(directory, case_number)
            expected = expected_output(records)
            result = run_script(["bash", ETL, input_path, output_path])
            assert result.returncode == 0, f"ETL failed on generated case {case_number}: {result.stderr}"
            assert os.path.isfile(output_path), f"ETL did not create output for generated case {case_number}"
            with open(output_path, "r") as handle:
                actual = handle.read().strip()
            assert actual == expected, f"Incorrect ETL result for generated case {case_number}.\nExpected:\n{expected}\n\nGot:\n{actual}"


def test_test_etl_script_execution():
    result = run_script(["bash", TEST_ETL])
    assert result.returncode == 0, f"The test script {TEST_ETL} failed with return code {result.returncode}."
    assert "PASS" in result.stdout, f"The test script did not print 'PASS'. Output: {result.stdout}"


def test_test_etl_actually_tests_etl():
    with tempfile.TemporaryDirectory(prefix="test-etl-probe-") as directory:
        backup = os.path.join(directory, "real_etl.sh")
        marker = os.path.join(directory, "invocation.txt")
        captured_input = os.path.join(directory, "captured.csv")
        shutil.copy2(ETL, backup)

        probe = f'''#!/bin/bash
printf '%s\\n' "$#" "$1" "$2" > {marker!r}
cp -- "$1" {captured_input!r} || true
exec bash {backup!r} "$@"
'''
        try:
            with open(ETL, "w") as handle:
                handle.write(probe)
            os.chmod(ETL, 0o755)

            result = run_script(["bash", TEST_ETL])
            assert result.returncode == 0, f"The test script failed while using a working ETL: {result.stderr}"
            assert "PASS" in result.stdout, f"The test script did not report PASS for a working ETL: {result.stdout}"
            assert os.path.isfile(marker), "The test script did not invoke /home/user/etl.sh"

            with open(marker, "r") as handle:
                invocation = handle.read().splitlines()
            assert len(invocation) >= 3 and int(invocation[0]) >= 2, "The test script did not pass input and output arguments to etl.sh"
            assert os.path.abspath(invocation[1]) != RAW, "The test script reused raw_events.csv instead of generating dummy input"
            assert os.path.isfile(captured_input), "The test script's dummy input could not be inspected"
            with open(captured_input, "r") as handle:
                dummy_lines = handle.read().splitlines()
            assert dummy_lines and dummy_lines[0] == "ID,Tags,Value", "The generated dummy CSV has the wrong header"
            assert len(dummy_lines) >= 2, "The generated dummy CSV contains no data rows"

            bad_etl = '''#!/bin/bash
printf 'Token,Sum,ValidCount,Mean\\nintentionally_wrong,999,1,999.00\\n' > "$2"
exit 0
'''
            with open(ETL, "w") as handle:
                handle.write(bad_etl)
            os.chmod(ETL, 0o755)

            bad_result = run_script(["bash", TEST_ETL])
            assert "FAIL" in bad_result.stdout, f"The test script did not report FAIL for incorrect ETL output: {bad_result.stdout}"
            assert "PASS" not in bad_result.stdout, f"The test script incorrectly reported PASS for incorrect ETL output: {bad_result.stdout}"
        finally:
            shutil.copy2(backup, ETL)
            os.chmod(ETL, os.stat(backup).st_mode & 0o777)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
