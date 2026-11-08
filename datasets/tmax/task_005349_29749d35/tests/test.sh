#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import pytest

BUILD_DIR = "/home/user/polyglot_build"
CANONICAL_INPUT = """3,apple,10
1,banana,20
3,apple,15
2,cherry,5
1,banana,5
"""


def run(cmd, *, input_text=None):
    return subprocess.run(
        cmd,
        cwd=BUILD_DIR,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=True,
    )


def load_json_file(path):
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")


def expected_processed(rows, arch):
    objects = [
        {"id": row_id, "name": name, "value": value, "arch": arch}
        for row_id, name, value in rows
    ]
    objects.sort(key=lambda obj: obj["id"])
    merged = []
    for obj in objects:
        if merged and merged[-1]["id"] == obj["id"]:
            merged[-1]["value"] += obj["value"]
        else:
            merged.append(dict(obj))
    return merged


def test_directory_exists():
    """Verify that the polyglot_build directory was created."""
    assert os.path.isdir(BUILD_DIR), f"Directory {BUILD_DIR} does not exist."


def test_source_files_exist():
    """Verify that the required source files exist."""
    required_files = ["parser.cpp", "processor.py", "Makefile", "input.txt"]
    for f in required_files:
        path = os.path.join(BUILD_DIR, f)
        assert os.path.isfile(path), f"Required file {path} is missing."


def test_executables_exist():
    """Verify that the Makefile 'all' target successfully compiled the executables."""
    for exe in ["parser_x86", "parser_arm"]:
        path = os.path.join(BUILD_DIR, exe)
        assert os.path.isfile(path), f"Executable {path} is missing. Did 'make all' run successfully?"
        assert os.access(path, os.X_OK), f"File {path} is not executable."
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable."


def test_output_x86_json():
    """Verify the contents of output_x86.json."""
    output_path = os.path.join(BUILD_DIR, "output_x86.json")
    assert os.path.isfile(output_path), f"Output file {output_path} is missing. Did 'make test' run successfully?"
    data = load_json_file(output_path)
    expected_data = [
        {"id": 1, "name": "banana", "value": 25, "arch": "x86"},
        {"id": 2, "name": "cherry", "value": 5, "arch": "x86"},
        {"id": 3, "name": "apple", "value": 25, "arch": "x86"},
    ]
    assert data == expected_data, f"Data in {output_path} does not match the expected output."


def test_output_arm_json():
    """Verify the contents of output_arm.json."""
    output_path = os.path.join(BUILD_DIR, "output_arm.json")
    assert os.path.isfile(output_path), f"Output file {output_path} is missing. Did 'make test' run successfully?"
    data = load_json_file(output_path)
    expected_data = [
        {"id": 1, "name": "banana", "value": 25, "arch": "arm"},
        {"id": 2, "name": "cherry", "value": 5, "arch": "arm"},
        {"id": 3, "name": "apple", "value": 25, "arch": "arm"},
    ]
    assert data == expected_data, f"Data in {output_path} does not match the expected output."


def test_randomized_make_pipeline_and_components():
    input_path = os.path.join(BUILD_DIR, "input.txt")
    token = secrets.token_hex(6)
    try:
        for trial in range(3):
            rng = random.SystemRandom()
            base = rng.randint(20, 1000000)
            ids = [base + i for i in range(4)]
            chosen_ids = [ids[2], ids[0], ids[3], ids[2], ids[1], ids[0], ids[1], ids[2]]
            rng.shuffle(chosen_ids)
            rows = []
            for index, row_id in enumerate(chosen_ids):
                rows.append((row_id, f"name_{token}_{trial}_{index}", rng.randint(-500, 900)))
            csv_text = "".join(f"{row_id},{name},{value}\n" for row_id, name, value in rows)
            with open(input_path, "w") as f:
                f.write(csv_text)

            run(["make", "test"])
            for arch in ("x86", "arm"):
                output_path = os.path.join(BUILD_DIR, f"output_{arch}.json")
                expected = expected_processed(rows, arch)
                assert load_json_file(output_path) == expected
                with open(output_path, "r") as f:
                    assert f.read() == json.dumps(expected, indent=2) + "\n"

                parser_result = run([f"./parser_{arch}"], input_text=csv_text)
                parsed = json.loads(parser_result.stdout)
                expected_parsed = [
                    {"id": row_id, "name": name, "value": value, "arch": arch}
                    for row_id, name, value in rows
                ]
                assert parsed == expected_parsed

                processor_result = run(["python3", "processor.py"], input_text=parser_result.stdout)
                assert json.loads(processor_result.stdout) == expected
                assert processor_result.stdout == json.dumps(expected, indent=2) + "\n"

        synthetic = [
            {"id": 9, "name": f"first_{token}", "value": 7, "arch": "one"},
            {"id": 2, "name": f"low_{token}", "value": -4, "arch": "low"},
            {"id": 9, "name": f"ignored_{token}", "value": 12, "arch": "two"},
            {"id": 2, "name": f"also_ignored_{token}", "value": 10, "arch": "other"},
        ]
        expected = [
            {"id": 2, "name": f"low_{token}", "value": 6, "arch": "low"},
            {"id": 9, "name": f"first_{token}", "value": 19, "arch": "one"},
        ]
        result = run(["python3", "processor.py"], input_text=json.dumps(synthetic))
        assert result.stdout == json.dumps(expected, indent=2) + "\n"
    finally:
        with open(input_path, "w") as f:
            f.write(CANONICAL_INPUT)
        run(["make", "test"])
TEST_EOF

if (
    set -e
    cd /home/user/polyglot_build
    printf '%s' '3,apple,10
1,banana,20
3,apple,15
2,cherry,5
1,banana,5
' > input.txt
    rm -f parser_x86 parser_arm output_x86.json output_arm.json
    make -B all
    make test
    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
