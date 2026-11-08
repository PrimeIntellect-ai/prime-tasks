#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile

PIPELINE_DIR = "/home/user/pipeline"
BUILD_FILE = os.path.join(PIPELINE_DIR, "build.sh")
TRANSFORM_FILE = os.path.join(PIPELINE_DIR, "transform.py")
INPUT_FILE = os.path.join(PIPELINE_DIR, "input.csv")
GOLDEN_FILE = os.path.join(PIPELINE_DIR, "golden.csv")

ORIGINAL_INPUT = "1.5\n2.5\n3.5\n4.5\n5.5\n6.5\n7.5\n8.5\n9.5\n10.5\n"
ORIGINAL_GOLDEN = "3.0\n5.0\n7.0\n9.0\n11.0\n13.0\n15.0\n17.0\n19.0\n21.0\n"


def test_protected_data_files_unchanged():
    with open(INPUT_FILE, "r") as f:
        assert f.read() == ORIGINAL_INPUT, "input.csv was modified."
    with open(GOLDEN_FILE, "r") as f:
        assert f.read() == ORIGINAL_GOLDEN, "golden.csv was modified."


def test_build_sh_success():
    assert os.path.isfile(BUILD_FILE), f"{BUILD_FILE} does not exist."

    result = subprocess.run([BUILD_FILE], capture_output=True, text=True)
    assert result.returncode == 0, f"build.sh failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert "BUILD SUCCESS" in result.stdout, "build.sh did not print 'BUILD SUCCESS'."


def test_final_output_matches_golden():
    final_output_file = os.path.join(PIPELINE_DIR, "final_output.csv")

    assert os.path.isfile(final_output_file), f"File {final_output_file} does not exist."
    assert os.path.isfile(GOLDEN_FILE), f"File {GOLDEN_FILE} does not exist."

    with open(final_output_file, "r") as f:
        final_content = f.read().strip()
    with open(GOLDEN_FILE, "r") as f:
        golden_content = f.read().strip()

    assert final_content == golden_content, "final_output.csv does not match golden.csv exactly."


def test_build_sh_precision_fix():
    with open(BUILD_FILE, "r") as f:
        content = f.read()

    assert "NUMPY_PRECISION=32" not in content, "build.sh still contains NUMPY_PRECISION=32."


def test_transform_py_truncation_fix():
    output_file = os.path.join(PIPELINE_DIR, "output.csv")
    assert os.path.isfile(output_file), f"{output_file} does not exist."

    with open(output_file, "r") as f:
        output_lines = [line for line in f if line.strip()]

    assert len(output_lines) == 10, f"Expected 10 lines in output.csv, but got {len(output_lines)}. The truncation bug might not be fully fixed."


def test_transform_on_derived_inputs_and_batch_sizes():
    assert os.path.isfile(TRANSFORM_FILE), f"{TRANSFORM_FILE} does not exist."
    values = [
        0.123456789012345,
        -7.75,
        1.0000000000001,
        3.141592653589793,
        2.718281828459045,
        100000.123456789,
        9.25,
    ]
    expected = "".join(f"{value * 2.0}\n" for value in values)

    for batch_size in (2, 3, 4, 8):
        with tempfile.TemporaryDirectory() as tmpdir:
            challenge_input = os.path.join(tmpdir, "input.csv")
            challenge_output = os.path.join(tmpdir, "output.csv")
            with open(challenge_input, "w") as f:
                f.write("".join(f"{value}\n" for value in values))

            env = os.environ.copy()
            env["NUMPY_PRECISION"] = "64"
            env["BATCH_SIZE"] = str(batch_size)
            result = subprocess.run(
                ["python3", TRANSFORM_FILE, challenge_input, challenge_output],
                capture_output=True,
                text=True,
                env=env,
            )
            assert result.returncode == 0, (
                f"transform.py failed for batch size {batch_size}.\n"
                f"Stdout: {result.stdout}\nStderr: {result.stderr}"
            )
            assert os.path.isfile(challenge_output), "transform.py did not create its requested output."
            with open(challenge_output, "r") as f:
                actual = f.read()
            assert actual == expected, (
                f"transform.py produced incorrect or truncated data for batch size {batch_size}."
            )


def test_build_executes_transformation_and_diff_with_float64():
    challenge_values = [
        0.123456789012345,
        -7.75,
        1.0000000000001,
        3.141592653589793,
        2.718281828459045,
        100000.123456789,
        9.25,
    ]
    challenge_input = "".join(f"{value}\n" for value in challenge_values)
    expected_output = "".join(f"{value * 2.0}\n" for value in challenge_values)
    deliberately_wrong_golden = "".join("999999.0\n" for _ in challenge_values)
    output_file = os.path.join(PIPELINE_DIR, "output.csv")

    with open(INPUT_FILE, "rb") as f:
        saved_input = f.read()
    with open(GOLDEN_FILE, "rb") as f:
        saved_golden = f.read()
    saved_output = None
    if os.path.exists(output_file):
        with open(output_file, "rb") as f:
            saved_output = f.read()

    try:
        with open(INPUT_FILE, "w") as f:
            f.write(challenge_input)
        with open(GOLDEN_FILE, "w") as f:
            f.write(deliberately_wrong_golden)

        mismatch = subprocess.run([BUILD_FILE], capture_output=True, text=True)
        assert mismatch.returncode != 0, "build.sh succeeded even though the generated data should not match golden.csv."
        assert "BUILD SUCCESS" not in mismatch.stdout, "build.sh printed BUILD SUCCESS for mismatched data."
        assert os.path.isfile(output_file), "build.sh did not produce output.csv by running the transformation."
        with open(output_file, "r") as f:
            assert f.read() == expected_output, "build.sh did not generate the derived float64 transformation output."

        with open(GOLDEN_FILE, "w") as f:
            f.write(expected_output)
        success = subprocess.run([BUILD_FILE], capture_output=True, text=True)
        assert success.returncode == 0, (
            f"build.sh failed on a derived valid dataset.\n"
            f"Stdout: {success.stdout}\nStderr: {success.stderr}"
        )
        assert "BUILD SUCCESS" in success.stdout, "build.sh did not print BUILD SUCCESS for matching derived data."
        with open(output_file, "r") as f:
            assert f.read() == expected_output, "build.sh output did not match the derived float64 result."
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(saved_input)
        with open(GOLDEN_FILE, "wb") as f:
            f.write(saved_golden)
        if saved_output is None:
            if os.path.exists(output_file):
                os.remove(output_file)
        else:
            with open(output_file, "wb") as f:
                f.write(saved_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
