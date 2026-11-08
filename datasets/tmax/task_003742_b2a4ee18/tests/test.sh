#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

OUTPUT_CSV = "/home/user/output.csv"
PIPELINE = "/home/user/etl_pipeline.py"
TEST_SCRIPT = "/home/user/test_reproducibility.sh"
LOG_FILE = "/home/user/reproducibility_log.txt"
RAW_CSV = "/home/user/data/raw.csv"
META_JSON = "/home/user/data/meta.json"
WEIGHTS_CSV = "/home/user/data/weights.csv"


def run_pipeline():
    result = subprocess.run(
        ["python3", PIPELINE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_output_csv_content():
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is missing."
    run_pipeline()
    assert os.path.isfile(OUTPUT_CSV), f"{OUTPUT_CSV} is missing."

    with open(OUTPUT_CSV, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "sample_id,out1,out2,out3",
        "S1,1.5,0.5,1.0",
        "S2,6.0,4.0,5.0",
        "S3,18.0,14.0,16.0"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {OUTPUT_CSV}, got {len(lines)}."
    for idx, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {idx + 1} in {OUTPUT_CSV} does not match expected output. Expected '{expected}', got '{actual}'."


def test_pipeline_on_derived_inputs():
    rng = random.SystemRandom()
    factors = {
        "7": rng.randint(2, 8) / 2.0,
        "11": rng.randint(9, 17) / 3.0,
        "999": rng.randint(18, 25) / 4.0,
    }
    features = [
        [rng.randint(-8, 9) for _ in range(3)]
        for _ in range(4)
    ]
    batch_ids = [7, None, 11, 7]
    weights = [
        [rng.randint(-4, 5) for _ in range(3)]
        for _ in range(3)
    ]

    paths = [RAW_CSV, META_JSON, WEIGHTS_CSV, OUTPUT_CSV]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()
        else:
            backups[path] = None

    try:
        with open(RAW_CSV, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["sample_id", "f1", "f2", "f3", "batch_id"])
            for i, (row, batch_id) in enumerate(zip(features, batch_ids), 1):
                writer.writerow([f"R{i}", *row, "" if batch_id is None else batch_id])

        with open(META_JSON, "w") as f:
            json.dump(factors, f)

        with open(WEIGHTS_CSV, "w", newline="") as f:
            csv.writer(f).writerows(weights)

        run_pipeline()

        expected = []
        for row, batch_id in zip(features, batch_ids):
            product = [
                sum(row[k] * weights[k][j] for k in range(3))
                for j in range(3)
            ]
            factor = factors[str(999 if batch_id is None else batch_id)]
            expected.append([value * factor for value in product])

        with open(OUTPUT_CSV, newline="") as f:
            rows = list(csv.reader(f))

        assert rows[0] == ["sample_id", "out1", "out2", "out3"]
        assert len(rows) == 5
        for i, (actual_row, expected_values) in enumerate(zip(rows[1:], expected), 1):
            assert actual_row[0] == f"R{i}"
            assert len(actual_row) == 4
            for actual, expected_value in zip(actual_row[1:], expected_values):
                assert float(actual) == pytest.approx(expected_value, rel=1e-10, abs=1e-10)
    finally:
        for path, content in backups.items():
            if content is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(content)


def test_reproducibility_script_exists_and_executable():
    assert os.path.isfile(TEST_SCRIPT), f"{TEST_SCRIPT} is missing."
    st = os.stat(TEST_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{TEST_SCRIPT} is not executable."


def test_reproducibility_log():
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is missing."
    assert os.path.isfile(TEST_SCRIPT), f"{TEST_SCRIPT} is missing."

    with tempfile.TemporaryDirectory(prefix="verifier-repro-") as tempdir:
        real_pipeline = os.path.join(tempdir, "submitted_pipeline.py")
        counter_file = os.path.join(tempdir, "count")
        expected_file = os.path.join(tempdir, "expected_hashes")
        shutil.copy2(PIPELINE, real_pipeline)

        saved_pipeline = open(PIPELINE, "rb").read()
        pipeline_mode = stat.S_IMODE(os.stat(PIPELINE).st_mode)
        saved_output = open(OUTPUT_CSV, "rb").read() if os.path.exists(OUTPUT_CSV) else None
        saved_log = open(LOG_FILE, "rb").read() if os.path.exists(LOG_FILE) else None

        proxy = f'''import hashlib
import os
import runpy

counter_file = {counter_file!r}
expected_file = {expected_file!r}
real_pipeline = {real_pipeline!r}
output_file = {OUTPUT_CSV!r}

try:
    with open(counter_file, "r") as f:
        count = int(f.read()) + 1
except FileNotFoundError:
    count = 1
with open(counter_file, "w") as f:
    f.write(str(count))

runpy.run_path(real_pipeline, run_name="__main__")
with open(output_file, "ab") as f:
    f.write(("# verifier execution %d\\n" % count).encode())
with open(output_file, "rb") as f:
    digest = hashlib.md5(f.read()).hexdigest()
with open(expected_file, "a") as f:
    f.write(digest + "\\n")
'''

        try:
            with open(PIPELINE, "w") as f:
                f.write(proxy)
            os.chmod(PIPELINE, pipeline_mode)
            try:
                os.remove(LOG_FILE)
            except FileNotFoundError:
                pass

            result = subprocess.run(
                ["bash", "-x", TEST_SCRIPT],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=45,
            )
            assert result.returncode == 0, (
                f"Reproducibility script failed with exit code {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

            assert os.path.isfile(counter_file), "The reproducibility script did not run the pipeline."
            with open(counter_file) as f:
                count = int(f.read())
            assert count == 3, f"Expected the pipeline to run exactly 3 times, but it ran {count} times."

            python_traces = re.findall(
                r"^\+ python3 /home/user/etl_pipeline\.py\s*$",
                result.stderr,
                flags=re.MULTILINE,
            )
            assert len(python_traces) == 3, (
                "The script must execute exactly 'python3 /home/user/etl_pipeline.py' three times."
            )

            md5_traces = re.findall(
                r"^\+ md5sum /home/user/output\.csv\s*$",
                result.stderr,
                flags=re.MULTILINE,
            )
            assert len(md5_traces) == 3, (
                "The script must invoke md5sum on /home/user/output.csv after each run."
            )

            assert os.path.isfile(LOG_FILE), f"{LOG_FILE} is missing."

            with open(LOG_FILE, "r") as f:
                lines = [line.strip() for line in f if line.strip()]

            assert len(lines) == 3, f"Expected exactly 3 lines in {LOG_FILE}, got {len(lines)}."

            with open(expected_file) as f:
                expected_hashes = [line.strip() for line in f if line.strip()]
            assert len(expected_hashes) == 3

            for idx, (line, expected_hash) in enumerate(zip(lines, expected_hashes)):
                assert line == f"{expected_hash}  /home/user/output.csv", (
                    f"Line {idx + 1} is not the standard md5sum output for the file produced "
                    "by the corresponding pipeline run."
                )

            # Calculate md5 of output.csv
            with open(OUTPUT_CSV, "rb") as f:
                file_hash = hashlib.md5(f.read()).hexdigest()

            for idx, line in enumerate(lines):
                parts = line.split()
                assert len(parts) >= 2, f"Line {idx + 1} in {LOG_FILE} is not a valid md5sum output."
                if idx == len(lines) - 1:
                    assert parts[0] == file_hash, f"Hash on line {idx + 1} in {LOG_FILE} does not match the actual MD5 hash of {OUTPUT_CSV}."
                assert "output.csv" in parts[1], f"Filename on line {idx + 1} in {LOG_FILE} does not reference output.csv."
        finally:
            with open(PIPELINE, "wb") as f:
                f.write(saved_pipeline)
            os.chmod(PIPELINE, pipeline_mode)
            if saved_output is None:
                try:
                    os.remove(OUTPUT_CSV)
                except FileNotFoundError:
                    pass
            else:
                with open(OUTPUT_CSV, "wb") as f:
                    f.write(saved_output)
            if saved_log is None:
                try:
                    os.remove(LOG_FILE)
                except FileNotFoundError:
                    pass
            else:
                with open(LOG_FILE, "wb") as f:
                    f.write(saved_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
