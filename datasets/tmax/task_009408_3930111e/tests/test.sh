#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile


def random_category(length=8):
    return ''.join(secrets.choice(string.ascii_letters) for _ in range(length))


def make_cases():
    base_id = secrets.randbelow(900000) + 1000
    valid_rows = [
        f"{base_id},0.0,{random_category()},0",
        f"{base_id + 1},100.0,{random_category()},1",
        f"{base_id + 2},{secrets.randbelow(9999) / 100:.2f},{random_category(10)},1",
        f"{base_id + 3},42.25,{random_category(1)},0",
    ]
    invalid_rows = [
        f"0,50.0,{random_category()},1",
        f"-{base_id},50.0,{random_category()},0",
        f"x{base_id},50.0,{random_category()},1",
        f"{base_id + 4},-0.01,{random_category()},1",
        f"{base_id + 5},100.01,{random_category()},0",
        f"{base_id + 6},notafloat,{random_category()},1",
        f"{base_id + 7},nan,{random_category()},0",
        f"{base_id + 8},50.0,,1",
        f"{base_id + 9},50.0,{random_category(11)},0",
        f"{base_id + 10},50.0,{random_category()},2",
        f"{base_id + 11},50.0,{random_category()},true",
        f"{base_id + 12},50.0,{random_category()}",
        f"{base_id + 13},50.0,{random_category()},1,extra",
        "",
    ]

    tagged = [(row, True) for row in valid_rows] + [(row, False) for row in invalid_rows]
    secrets.SystemRandom().shuffle(tagged)
    input_text = '\n'.join(row for row, _ in tagged) + '\n'
    expected_text = '\n'.join(row for row, valid in tagged if valid) + '\n'
    return input_text, expected_text


def run_cleaner(executable):
    input_text, expected_text = make_cases()
    result = subprocess.run(
        [executable], input=input_text, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Cleaner {executable} exited with {result.returncode}. Stderr: {result.stderr}"
    )
    assert result.stdout.strip() == expected_text.strip(), (
        f"Cleaner failed generated schema cases.\n"
        f"Input:\n{input_text}\nExpected:\n{expected_text}\nGot:\n{result.stdout}"
    )


def test_cleaner_cpp_exists():
    assert os.path.isfile("/home/user/cleaner.cpp"), "C++ source file /home/user/cleaner.cpp is missing."


def test_run_pipeline_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Pipeline script {script_path} is not executable."


def test_pipeline_execution_and_output():
    script_path = "/home/user/run_pipeline.sh"
    output_file = "/home/user/clean_data.csv"

    if os.path.exists(output_file):
        os.remove(output_file)

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed with exit code {result.returncode}. Stderr: {result.stderr}"

    assert os.path.isfile(output_file), f"Output file {output_file} was not created by the pipeline script."

    expected_output = (
        "1,45.5,alpha,1\n"
        "3,0.0,delta,0\n"
        "7,10.0,eta,1\n"
        "9,55.5,iota,0\n"
        "10,100.0,kappa,1\n"
    )

    with open(output_file, "r") as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output.strip(), (
        f"Cleaned data mismatch.\nExpected:\n{expected_output}\nGot:\n{actual_output}"
    )


def test_compiled_executable_exists():
    executable_path = "/home/user/cleaner"
    assert os.path.isfile(executable_path), f"Compiled executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"Compiled executable {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled ELF executable."


def test_cleaner_source_and_installed_executable_on_generated_inputs():
    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, "cleaner")
        result = subprocess.run(
            ["g++", "-O3", "-std=c++17", "/home/user/cleaner.cpp", "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"cleaner.cpp failed to compile. Stderr: {result.stderr}"
        run_cleaner(rebuilt)

    run_cleaner("/home/user/cleaner")


def test_pipeline_on_generated_input_and_rebuilds_cleaner():
    raw_path = "/home/user/raw_data.csv"
    output_path = "/home/user/clean_data.csv"
    executable_path = "/home/user/cleaner"
    with open(raw_path, "rb") as f:
        original_raw = f.read()

    input_text, expected_text = make_cases()
    try:
        with open(raw_path, "w") as f:
            f.write(input_text)
        if os.path.exists(output_path):
            os.remove(output_path)
        if os.path.exists(executable_path):
            os.remove(executable_path)

        result = subprocess.run(
            ["/home/user/run_pipeline.sh"], capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, (
            f"Pipeline failed on generated input with exit code {result.returncode}. "
            f"Stderr: {result.stderr}"
        )
        assert os.path.isfile(executable_path), "Pipeline did not rebuild /home/user/cleaner."
        assert os.access(executable_path, os.X_OK), "Rebuilt cleaner is not executable."
        with open(executable_path, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Pipeline did not produce a compiled ELF cleaner."
        assert os.path.isfile(output_path), "Pipeline did not create /home/user/clean_data.csv."
        with open(output_path, "r") as f:
            actual_output = f.read()
        assert actual_output.strip() == expected_text.strip(), (
            f"Pipeline failed generated schema cases.\n"
            f"Input:\n{input_text}\nExpected:\n{expected_text}\nGot:\n{actual_output}"
        )
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
