#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import time
import json
import subprocess
import csv
import io
import secrets
import uuid


def test_directories_exist():
    """Verify that the required directories have been created."""
    assert os.path.isdir("/home/user/raw_datasets"), "/home/user/raw_datasets directory does not exist."
    assert os.path.isdir("/home/user/clean_datasets"), "/home/user/clean_datasets directory does not exist."


def test_script_exists_and_executable():
    """Verify that the auto_process.sh script exists and is executable."""
    script_path = "/home/user/auto_process.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_script_is_running():
    """Verify that the script is running in the background."""
    try:
        ps_output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    except subprocess.CalledProcessError:
        assert False, "Failed to run 'ps aux' to check running processes."

    assert "auto_process.sh" in ps_output, "The script auto_process.sh does not appear to be running in the background."


def test_processing_behavior():
    """Verify the original TSV to JSON conversion case."""
    tsv_data = "SampleID\tMeasurement\tTimestamp\nX-100\t99.9\t2023-11-01T12:00:00Z\nY-200\t-4.5\t2023-11-01T12:05:00Z\n"
    input_path = "/home/user/raw_datasets/test_experiment_99.tsv"
    output_path = "/home/user/clean_datasets/test_experiment_99.json"

    if os.path.exists(output_path):
        os.remove(output_path)

    with open(input_path, "w", encoding="utf-16le") as f:
        f.write(tsv_data)

    timeout = 5.0
    start_time = time.time()
    while time.time() - start_time < timeout:
        if os.path.exists(output_path):
            break
        time.sleep(0.5)

    assert os.path.exists(output_path), f"Output file {output_path} was not created within {timeout} seconds."

    with open(output_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Output file {output_path} does not contain valid JSON."

    expected_data = [
        {"SampleID": "X-100", "Measurement": "99.9", "Timestamp": "2023-11-01T12:00:00Z"},
        {"SampleID": "Y-200", "Measurement": "-4.5", "Timestamp": "2023-11-01T12:05:00Z"}
    ]

    assert data == expected_data, f"Data mismatch. Expected {expected_data}, got {data}"


def _encode_tsv(headers, rows):
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, delimiter="\t", quotechar='"', lineterminator="\n")
    writer.writerow(headers)
    for row in rows:
        writer.writerow([row[h] for h in headers])
    return stream.getvalue().encode("utf-16le")


def test_random_new_files_and_standard_tsv_parsing():
    """Exercise unpredictable filenames, values, UTF-16LE text, and quoted TSV fields."""
    nonce = secrets.token_hex(12)
    key_a = "sample_" + secrets.token_hex(3)
    key_b = "notes_" + secrets.token_hex(3)
    key_c = "reading_" + secrets.token_hex(3)
    headers = [key_a, key_b, key_c]

    cases = [
        [
            {key_a: "Δ-" + nonce, key_b: "contains\ta tab", key_c: "測定-" + secrets.token_hex(4)},
            {key_a: "échantillon-" + secrets.token_hex(4), key_b: 'contains "quotes"', key_c: "-" + str(secrets.randbelow(100000))},
        ],
        [
            {key_a: "研究-" + secrets.token_hex(5), key_b: "ordinary " + secrets.token_hex(8), key_c: str(secrets.randbelow(10**9))},
            {key_a: "Ω-" + secrets.token_hex(5), key_b: "second\tfield " + secrets.token_hex(5), key_c: "值-" + secrets.token_hex(3)},
            {key_a: secrets.token_hex(9), key_b: 'a "quoted" note', key_c: str(-secrets.randbelow(10**8))},
        ],
    ]

    pending = {}
    for rows in cases:
        base = "incoming_" + uuid.uuid4().hex
        input_path = f"/home/user/raw_datasets/{base}.tsv"
        output_path = f"/home/user/clean_datasets/{base}.json"
        assert not os.path.exists(output_path)
        payload = _encode_tsv(headers, rows)
        with open(input_path, "wb") as f:
            f.write(payload)
        pending[output_path] = rows

    deadline = time.time() + 8.0
    last_errors = {}
    while pending and time.time() < deadline:
        for output_path, expected in list(pending.items()):
            if not os.path.exists(output_path):
                continue
            try:
                with open(output_path, "r", encoding="utf-8") as f:
                    actual = json.load(f)
                if actual == expected:
                    del pending[output_path]
                else:
                    last_errors[output_path] = f"expected {expected!r}, got {actual!r}"
            except (OSError, UnicodeError, json.JSONDecodeError) as exc:
                last_errors[output_path] = repr(exc)
        if pending:
            time.sleep(0.1)

    assert not pending, "Random TSV files were not correctly processed: " + "; ".join(
        f"{path}: {last_errors.get(path, 'output was not created')}" for path in pending
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
