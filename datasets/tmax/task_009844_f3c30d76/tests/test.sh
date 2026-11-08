#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile


def test_final_output_exists():
    assert os.path.isfile("/home/user/final_output.txt"), "/home/user/final_output.txt is missing. Did you run the pipeline script?"


def test_final_output_content():
    expected_content = (
        "data_01.csv,335.000000\n"
        "data_02.csv,50.000000\n"
        "data_03.csv,10.000000"
    )

    with open("/home/user/final_output.txt", "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of /home/user/final_output.txt is incorrect or not sorted properly.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{actual_content}"
    )


def test_integrator_and_pipeline_on_independent_inputs():
    awk_path = "/home/user/integrate.awk"
    pipeline_path = "/home/user/pipeline.sh"
    data_path = "/home/user/data"
    output_path = "/home/user/final_output.txt"

    assert os.path.isfile(awk_path), f"{awk_path} is missing or is not a regular file"
    assert os.path.isfile(pipeline_path), f"{pipeline_path} is missing or is not a regular file"
    assert stat.S_ISREG(os.stat(awk_path).st_mode)
    assert stat.S_ISREG(os.stat(pipeline_path).st_mode)
    assert os.access(pipeline_path, os.X_OK), f"{pipeline_path} is not executable"

    with tempfile.TemporaryDirectory() as td:
        probe = os.path.join(td, "irregular.csv")
        with open(probe, "w") as f:
            f.write("0,2\n1,4\n3,10\n6,-2\n")
        result = subprocess.run(
            ["awk", "-f", awk_path, probe],
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout == "29.000000\n", (
            "integrate.awk did not apply the trapezoidal rule with exactly six decimals"
        )

    backup_root = tempfile.mkdtemp(prefix="pipeline-verifier-")
    backup_data = os.path.join(backup_root, "data")
    output_existed = os.path.exists(output_path)
    output_bytes = None
    if output_existed:
        with open(output_path, "rb") as f:
            output_bytes = f.read()

    try:
        shutil.move(data_path, backup_data)
        os.mkdir(data_path)

        expected_lines = []
        for index in range(16):
            name = f"case_{index:02d}.csv"
            # The first file is deliberately much larger, exposing wrappers that
            # append parallel results in completion order instead of sorting them.
            rows = 40000 if index == 0 else index + 2
            constant = index + 1
            with open(os.path.join(data_path, name), "w") as f:
                for t in range(rows):
                    f.write(f"{t},{2 * t + constant}\n")
            end = rows - 1
            integral = end * end + constant * end
            expected_lines.append(f"{name},{integral:.6f}")

        expected = "\n".join(sorted(expected_lines))
        observed = []
        for run_number in range(3):
            with open(output_path, "w") as f:
                f.write(f"stale-output-{run_number}\n")
            result = subprocess.run(
                [pipeline_path],
                text=True,
                capture_output=True,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"pipeline.sh failed with exit code {result.returncode}: {result.stderr}"
            )
            assert os.path.isfile(output_path), "pipeline.sh did not create final_output.txt"
            with open(output_path, "r") as f:
                actual = f.read().strip()
            assert actual == expected, (
                "pipeline.sh did not produce independently calculated trapezoidal "
                "results sorted alphabetically by filename\n"
                f"Expected:\n{expected}\nGot:\n{actual}"
            )
            observed.append(actual)

        assert len(set(observed)) == 1, "pipeline output changed between repeated runs"
    finally:
        if os.path.isdir(data_path):
            shutil.rmtree(data_path)
        if os.path.exists(backup_data):
            shutil.move(backup_data, data_path)
        if output_existed:
            with open(output_path, "wb") as f:
                f.write(output_bytes)
        elif os.path.exists(output_path):
            os.remove(output_path)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
