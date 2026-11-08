#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
import tempfile


def derive_expected():
    metadata = {}
    with open("/home/user/metadata.csv", "r", encoding="utf-8") as f:
        for row in csv.reader(f):
            if len(row) >= 2:
                metadata[row[0].strip()] = row[1].strip()

    expected_rows = []
    sensor_data_dir = "/home/user/sensor_data"
    for filename in os.listdir(sensor_data_dir):
        if filename.startswith("floor_") and filename.endswith(".csv"):
            filepath = os.path.join(sensor_data_dir, filename)
            with open(filepath, "r", encoding="utf-8") as f:
                reader = csv.reader(f)
                header = next(reader, None)
                if not header:
                    continue
                for row in reader:
                    if not row or not "".join(row).strip():
                        continue
                    timestamp = row[0].strip()
                    for i in range(1, len(row)):
                        sensor_id = header[i].strip()
                        value = row[i].strip()
                        sensor_type = metadata.get(sensor_id, "")
                        expected_rows.append((int(timestamp), sensor_id, sensor_type, value))

    expected_rows.sort(key=lambda x: (x[0], x[1]))
    return [f"{r[0]},{r[1]},{r[2]},{r[3]}" for r in expected_rows]


def read_actual():
    with open("/home/user/final_output.csv", "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def assert_final_output_correct():
    expected_lines = derive_expected()
    actual_lines = read_actual()
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} rows in final_output.csv, "
        f"but found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1} in final_output.csv.\n"
            f"Expected: {expected}\nGot:      {actual}"
        )


def test_reshape_c_exists():
    assert os.path.isfile("/home/user/reshape.c"), "The C source file /home/user/reshape.c is missing."


def test_reshape_executable_exists():
    assert os.path.isfile("/home/user/reshape"), "The compiled executable /home/user/reshape is missing."
    assert os.access("/home/user/reshape", os.X_OK), "The file /home/user/reshape is not executable."
    with open("/home/user/reshape", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/reshape is not a compiled ELF executable."


def test_workflow_sh_exists():
    assert os.path.isfile("/home/user/workflow.sh"), "The bash script /home/user/workflow.sh is missing."


def test_final_output_exists():
    assert os.path.isfile("/home/user/final_output.csv"), "The final output file /home/user/final_output.csv is missing."


def test_final_output_correctness():
    assert_final_output_correct()


def test_reshape_source_and_executable_behavior():
    sample = (
        "timestamp,ZVA,ZVB\n"
        "17,1.25,9.5\n"
        "\n"
        "3,-2,0.125\n"
    )
    expected = (
        "17,ZVA,1.25\n"
        "17,ZVB,9.5\n"
        "3,ZVA,-2\n"
        "3,ZVB,0.125\n"
    )

    for executable in ["/home/user/reshape"]:
        result = subprocess.run(
            [executable], input=sample, text=True, capture_output=True, timeout=10
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout == expected

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "reshape")
        build = subprocess.run(
            ["gcc", "/home/user/reshape.c", "-o", rebuilt],
            text=True, capture_output=True, timeout=30
        )
        assert build.returncode == 0, f"reshape.c does not compile:\n{build.stderr}"
        result = subprocess.run(
            [rebuilt], input=sample, text=True, capture_output=True, timeout=10
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout == expected


def test_workflow_uses_reshape_and_parallel_processing():
    with open("/home/user/workflow.sh", "r", encoding="utf-8") as f:
        script = f.read()
    assert re.search(r"(^|[/\s])reshape(?:\s|$)", script), "workflow.sh does not invoke reshape."
    background_and_wait = (
        re.search(r"(?<![>&])&(?![>&])", script) is not None
        and re.search(r"\bwait\b", script) is not None
    )
    xargs_parallel = re.search(r"\bxargs\b[^\n]*(?:-P\s*\d+|--max-procs(?:=|\s+)\d+)", script) is not None
    assert background_and_wait or xargs_parallel, "workflow.sh does not process files in parallel."


def test_workflow_recomputes_output_for_new_inputs():
    timestamp = 2000 + secrets.randbelow(7000)
    value_a = f"{secrets.randbelow(9000) + 1000}.125"
    value_b = f"-{secrets.randbelow(9000) + 1000}.75"

    metadata_path = "/home/user/metadata.csv"
    with open(metadata_path, "r", encoding="utf-8") as f:
        existing = [line for line in f if not line.startswith(("ZVA,", "ZVB,"))]
    with open(metadata_path, "w", encoding="utf-8") as f:
        f.writelines(existing)
        if existing and not existing[-1].endswith("\n"):
            f.write("\n")
        f.write("ZVA,verification_alpha\nZVB,verification_beta\n")

    with open("/home/user/sensor_data/floor_verify.csv", "w", encoding="utf-8") as f:
        f.write("timestamp,ZVA,ZVB\n")
        f.write(f"{timestamp + 1},{value_a},{value_b}\n")
        f.write("\n")
        f.write(f"{timestamp},{value_b},{value_a}\n")

    if os.path.exists("/home/user/final_output.csv"):
        os.remove("/home/user/final_output.csv")

    result = subprocess.run(
        ["bash", "/home/user/workflow.sh"],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert result.returncode == 0, f"workflow.sh failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile("/home/user/final_output.csv"), "workflow.sh did not recreate final_output.csv."
    assert_final_output_correct()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
