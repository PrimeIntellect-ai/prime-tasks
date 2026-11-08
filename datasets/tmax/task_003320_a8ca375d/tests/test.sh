#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

EXPECTED_ORIGINAL = """id,out1,out2,out3
1,1.5000,2.4000,3.8000
2,3.9000,6.9000,8.3000
3,6.3000,11.4000,12.8000"""


def test_processed_data_csv_correct():
    file_path = "/home/user/processed_data.csv"
    assert os.path.isfile(file_path), f"File missing: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_ORIGINAL, f"Content of {file_path} does not match expected output."


def test_etl_c_exists():
    file_path = "/home/user/etl.c"
    assert os.path.isfile(file_path), f"C source file missing: {file_path}"


def test_pipeline_script():
    script_path = "/home/user/test_pipeline.sh"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    for path in ("/home/user/etl_bin", "/home/user/processed_data.csv"):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"Script {script_path} failed with return code {result.returncode}. Stderr: {result.stderr}"

    output = result.stdout.strip()
    assert "PIPELINE PASS" in output, f"Script did not print 'PIPELINE PASS'. Output was: {output}"
    assert os.path.isfile("/home/user/etl_bin"), "Pipeline script did not create /home/user/etl_bin"
    assert os.access("/home/user/etl_bin", os.X_OK), "/home/user/etl_bin is not executable"
    assert os.path.isfile("/home/user/processed_data.csv"), "Pipeline script did not create processed_data.csv"
    with open("/home/user/processed_data.csv", "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_ORIGINAL, "Pipeline script did not reproduce the required output"
    assert len(content.splitlines()) == 4, "Pipeline output does not contain exactly four lines"


def test_compiled_etl_on_altered_inputs():
    raw_path = "/home/user/raw_data.csv"
    matrix_path = "/home/user/transform.csv"
    output_path = "/home/user/processed_data.csv"
    binary_path = "/tmp/etl_verifier_bin"

    with open(raw_path, "rb") as f:
        original_raw = f.read()
    with open(matrix_path, "rb") as f:
        original_matrix = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    compile_result = subprocess.run(
        ["gcc", "/home/user/etl.c", "-o", binary_path, "-lm"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"etl.c did not compile: {compile_result.stderr}"

    # Quarter-valued matrix entries make all expected values exactly representable,
    # while runtime-generated data prevents hardcoding the verifier's answers.
    matrix_ints = [[secrets.randbelow(12) + 1 for _ in range(3)] for _ in range(3)]
    matrix = [[value / 4.0 for value in row] for row in matrix_ints]
    rows = []
    for index in range(6):
        features = [secrets.randbelow(40) + 1 for _ in range(3)]
        rows.append((700 + index, features))

    raw_text = "id,f1,f2,f3\n" + "\n".join(
        f"{row_id},{features[0]}.0,{features[1]}.0,{features[2]}.0"
        for row_id, features in rows
    ) + "\n"
    matrix_text = "\n".join(
        ",".join(str(value) for value in matrix_row) for matrix_row in matrix
    ) + "\n"

    expected_lines = ["id,out1,out2,out3"]
    for row_id, features in rows:
        outputs = [
            sum(features[r] * matrix[r][column] for r in range(3))
            for column in range(3)
        ]
        expected_lines.append(
            f"{row_id},{outputs[0]:.4f},{outputs[1]:.4f},{outputs[2]:.4f}"
        )
    expected = "\n".join(expected_lines)

    try:
        with open(raw_path, "w") as f:
            f.write(raw_text)
        with open(matrix_path, "w") as f:
            f.write(matrix_text)
        if os.path.exists(output_path):
            os.remove(output_path)

        run_result = subprocess.run(
            [binary_path], cwd="/home/user", capture_output=True, text=True, timeout=20
        )
        assert run_result.returncode == 0, f"Compiled ETL failed: {run_result.stderr}"
        assert os.path.isfile(output_path), "Compiled ETL did not create processed_data.csv"
        with open(output_path, "r") as f:
            actual = f.read().strip()
        assert actual == expected, f"ETL output was incorrect on altered inputs.\nExpected:\n{expected}\nActual:\n{actual}"
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        with open(matrix_path, "wb") as f:
            f.write(original_matrix)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
