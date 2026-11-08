#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile

PIPELINE = "/home/user/etl_pipeline"
EXE = os.path.join(PIPELINE, "filter")
SRC = os.path.join(PIPELINE, "filter.c")


def run_filter(path, input_data):
    result = subprocess.run(
        [path],
        input=input_data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"Filter exited with status {result.returncode}. stderr:\n{result.stderr}"
    )
    return result.stdout


def randomized_case():
    ids = [
        0,
        2**32 + 17,
        2**53 + 123,
        2**63 + 987654321,
        2**64 - 1,
    ]
    while len(ids) < 15:
        candidate = secrets.randbits(64)
        if candidate not in ids:
            ids.append(candidate)

    tenths = [505, 100, 999, 250, 199, 200, 201, -35, 777, 1, 314, 205, 204, 890, 150]
    rows = list(zip(ids, tenths))
    input_data = "id,value\n" + "".join(
        f"{row_id},{value_tenths / 10:.1f}\n"
        for row_id, value_tenths in rows
    )
    expected = "id,value\n" + "".join(
        f"{row_id},{value_tenths / 10:.1f}\n"
        for row_id, value_tenths in rows
        if value_tenths > 200
    )
    return input_data, expected


def test_output_csv_correct():
    output_path = os.path.join(PIPELINE, "output.csv")
    assert os.path.isfile(output_path), f"File {output_path} does not exist. Did you run the filter program?"

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "id,value",
        "20000001,50.5",
        "20000003,99.9",
        "20000004,25.0"
    ]

    assert lines == expected_lines, f"Output CSV content is incorrect.\nExpected: {expected_lines}\nGot: {lines}"


def test_validation_log_pass():
    log_path = os.path.join(PIPELINE, "validation.log")
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did you run the validation script?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert "PASS" in content, f"validation.log does not contain 'PASS'. Actual content:\n{content}"


def test_filter_c_fixed():
    assert os.path.isfile(SRC), f"File {SRC} does not exist."

    with open(SRC, "r") as f:
        content = f.read()

    assert "float id_float;" not in content, "filter.c still contains the buggy 'float id_float;' declaration. You must fix the precision loss issue."
    assert "sscanf" in content, "filter.c should still use sscanf to parse the line, but correctly."

    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.DOTALL)
    assert re.search(r"\bsscanf\s*\(", without_comments), "filter.c only mentions sscanf in a comment; it must actually call sscanf."


def test_executable_compiled():
    assert os.path.isfile(EXE), f"Executable {EXE} does not exist. Did you run 'make'?"
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    mode = os.stat(EXE, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), "filter must be a regular compiled executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "filter is not a compiled ELF executable. Did you run 'make'?"


def test_generated_output_is_from_working_filter():
    with open(os.path.join(PIPELINE, "data.csv"), "r") as f:
        raw_data = f.read()
    with open(os.path.join(PIPELINE, "output.csv"), "r") as f:
        saved_output = f.read()
    assert run_filter(EXE, raw_data) == saved_output, "output.csv does not match the output produced by the submitted filter on data.csv."


def test_submitted_executable_handles_unseen_uint64_ids():
    input_data, expected = randomized_case()
    actual = run_filter(EXE, input_data)
    assert actual == expected, f"Submitted filter corrupts or incorrectly filters unseen uint64_t IDs.\nExpected:\n{expected}\nGot:\n{actual}"


def test_corrected_source_handles_unseen_uint64_ids():
    input_data, expected = randomized_case()
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "filter_from_source")
        result = subprocess.run(
            ["gcc", "-O2", "-Wall", SRC, "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        assert result.returncode == 0, f"Corrected filter.c does not compile. stderr:\n{result.stderr}"
        actual = run_filter(rebuilt, input_data)
        assert actual == expected, f"A fresh build of filter.c corrupts or incorrectly filters unseen uint64_t IDs.\nExpected:\n{expected}\nGot:\n{actual}"


def test_validation_script_accepts_output():
    result = subprocess.run(
        ["python3", "validate.py", "output.csv"],
        cwd=PIPELINE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, f"Validation script failed. stderr:\n{result.stderr}"
    assert "PASS" in result.stdout and "FAIL" not in result.stdout, f"Validation script did not accept output.csv:\n{result.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
