#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def test_script_exists_and_executable():
    script_path = "/home/user/process_pipeline.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_raw_data_synced():
    raw_dir = "/home/user/raw_data"
    staging_dir = "/opt/staging_server/data"

    assert os.path.isdir(raw_dir), f"The directory {raw_dir} does not exist."

    staging_files = [f for f in os.listdir(staging_dir) if f.endswith('.csv')]
    raw_files = [f for f in os.listdir(raw_dir) if f.endswith('.csv')]

    for f in staging_files:
        assert f in raw_files, f"File {f} was not synced to {raw_dir}."

    for f in staging_files:
        staging_size = os.path.getsize(os.path.join(staging_dir, f))
        raw_size = os.path.getsize(os.path.join(raw_dir, f))
        assert staging_size == raw_size, f"File {f} in {raw_dir} does not match the size of the original file."


def test_cleaned_master_csv():
    output_path = "/home/user/cleaned_master.csv"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"The file {output_path} is empty."
    assert lines[0] == "id,name,date,country", f"The header in {output_path} is incorrect. Got: {lines[0]}"

    expected_data = [
        "101,Alice Smith,2023-05-12,US",
        "102,Charlie,2022-12-31,FR",
        "103,Bob Jones,2023-04-10,UK",
        "201,Diana,2023-01-05,DE",
        "202,Evan,2023-06-15,AU"
    ]

    actual_data = lines[1:]
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} data rows, but got {len(actual_data)}."

    for i, (expected, actual) in enumerate(zip(expected_data, actual_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"


def test_pipeline_log():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        content = f.read()

    staging_dir = "/opt/staging_server/data"
    num_files = len([f for f in os.listdir(staging_dir) if f.endswith('.csv')])
    num_rows = 5

    pattern1 = rf"^\[\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}\] TRANSFER: Successfully synced {num_files} files\.$"
    pattern2 = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] PROCESS: Starting normalization\.$"
    pattern3 = rf"^\[\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}\] COMPLETE: Processed total of {num_rows} valid rows\.$"

    assert re.search(pattern1, content, re.MULTILINE), f"Log file missing or incorrectly formatted Stage 1 message for {num_files} files."
    assert re.search(pattern2, content, re.MULTILINE), "Log file missing or incorrectly formatted Stage 2 message."
    assert re.search(pattern3, content, re.MULTILINE), f"Log file missing or incorrectly formatted Stage 3 message for {num_rows} valid rows."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_dynamic_pipeline.py
import os
import random
import re
import secrets
import shutil
import subprocess


def normalize(row):
    ident, name, date, country = row
    if not ident.isdigit():
        return None
    if '/' in date:
        month, day, year = date.split('/')
        date = f"{year}-{month}-{day}"
    return f"{ident},{name.strip()},{date},{country.strip().upper()}"


def test_pipeline_executes_correctly_on_fresh_inputs():
    script = "/home/user/process_pipeline.sh"
    staging = "/opt/staging_server/data"
    raw = "/home/user/raw_data"
    output = "/home/user/cleaned_master.csv"
    log = "/home/user/pipeline.log"

    assert os.path.isfile(script)
    assert os.access(script, os.X_OK)

    token = secrets.token_hex(4)
    ids = random.sample(range(310, 990), 6)
    fixtures = {
        f"incoming_{token}_a.csv": [
            (str(ids[3]), f"  Alpha {token}  ", "07/14/2021", " uS "),
            (f"bad{token}", "Discard One", "01/01/2020", "ca"),
            (str(ids[0]), f"Beta {token} ", "2024-02-29", " ca"),
        ],
        f"incoming_{token}_b.csv": [
            (str(ids[5]), f" Gamma {token}", "11/03/2022", "Uk "),
            ("", "Discard Two", "2020-12-12", "fr"),
            (str(ids[1]), f"Delta {token}", "2023-08-09", " de "),
        ],
        f"incoming_{token}_c.csv": [
            (str(ids[4]), f"  Epsilon {token}", "03/22/2020", "Au"),
            (str(ids[2]), f"Zeta {token}  ", "2022-10-31", " jp "),
        ],
    }

    os.makedirs(staging, exist_ok=True)
    for name in os.listdir(staging):
        if name.endswith('.csv'):
            os.remove(os.path.join(staging, name))

    snapshots = {}
    all_rows = []
    for filename, rows in fixtures.items():
        text = "id,name,date,country\n" + "".join(",".join(row) + "\n" for row in rows)
        path = os.path.join(staging, filename)
        with open(path, "w") as handle:
            handle.write(text)
        snapshots[filename] = text
        all_rows.extend(rows)

    shutil.rmtree(raw, ignore_errors=True)
    for path in (output, log):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [script], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"Pipeline exited with {result.returncode}. stdout={result.stdout!r} "
        f"stderr={result.stderr!r}"
    )

    assert os.path.isdir(raw), "Pipeline did not create the raw_data directory."
    for filename, original in snapshots.items():
        copied = os.path.join(raw, filename)
        assert os.path.isfile(copied), f"Pipeline did not sync {filename}."
        with open(copied) as handle:
            assert handle.read() == original, f"Synced file {filename} differs from staging."

    expected_rows = [normalize(row) for row in all_rows]
    expected_rows = [row for row in expected_rows if row is not None]
    expected_rows.sort(key=lambda row: int(row.split(',', 1)[0]))

    assert os.path.isfile(output), "Pipeline did not create cleaned_master.csv."
    with open(output) as handle:
        actual_lines = [line.strip() for line in handle if line.strip()]
    assert actual_lines == ["id,name,date,country"] + expected_rows

    assert os.path.isfile(log), "Pipeline did not create pipeline.log."
    with open(log) as handle:
        content = handle.read()

    timestamp = r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]"
    transfer = rf"^{timestamp} TRANSFER: Successfully synced {len(fixtures)} files\.$"
    process = rf"^{timestamp} PROCESS: Starting normalization\.$"
    complete = rf"^{timestamp} COMPLETE: Processed total of {len(expected_rows)} valid rows\.$"
    assert re.search(transfer, content, re.MULTILINE)
    assert re.search(process, content, re.MULTILINE)
    assert re.search(complete, content, re.MULTILINE)

    valid_line = re.compile(rf"^{timestamp} [A-Z]+: .+$")
    for line in content.splitlines():
        if line:
            assert valid_line.fullmatch(line), f"Malformed log line: {line!r}"
TEST_EOF

ok=1
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_pipeline.py -x --tb=short 2>&1 || ok=0
fi

echo "$ok" > /logs/verifier/reward.txt
