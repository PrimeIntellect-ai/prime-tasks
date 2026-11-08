#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import secrets
import shutil
import subprocess
import tempfile
from collections import Counter, defaultdict

HEADER = ["timestamp", "sensor_id", "value", "status"]


def test_scripts_exist_and_executable():
    scripts = [
        "/home/user/validate.sh",
        "/home/user/process.sh",
        "/home/user/setup_cron.sh",
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def run_validator(path):
    return subprocess.run(
        ["/home/user/validate.sh", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).returncode


def test_validate_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]

    clean_failed = [os.path.basename(path) for path in clean_files if run_validator(path) != 0]
    evil_failed = [os.path.basename(path) for path in evil_files if run_validator(path) == 0]

    assert not clean_failed, (
        f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: "
        + ", ".join(clean_failed)
    )
    assert not evil_failed, (
        f"{len(evil_failed)} of {len(evil_files)} evil bypassed: "
        + ", ".join(evil_failed)
    )


def test_validate_unseen_content_and_names():
    token = secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix="validator-neutral-") as directory:
        cases = []

        # Retain the corpus classifications while removing corpus path/name cues.
        for kind, expected_clean in (("clean", True), ("evil", False)):
            source_dir = f"/app/corpus/{kind}"
            for source_name in os.listdir(source_dir):
                if not source_name.endswith(".csv"):
                    continue
                destination = os.path.join(directory, secrets.token_hex(10) + ".dat")
                shutil.copyfile(os.path.join(source_dir, source_name), destination)
                cases.append((destination, expected_clean))

        # Add unpredictable, newly generated examples so fixed-content classification fails.
        for index in range(4):
            clean_path = os.path.join(directory, secrets.token_hex(10) + ".bin")
            with open(clean_path, "w", newline="") as handle:
                writer = csv.writer(handle, lineterminator="\n")
                writer.writerow(HEADER)
                for row in range(1 + index):
                    writer.writerow([
                        f"2025-07-{index + 10:02d}T{row + 2:02d}:17:31Z",
                        f"sensor-{token}-{index}-{row}",
                        f"{secrets.randbelow(9000) / 10:.1f}",
                        "OK",
                    ])
            cases.append((clean_path, True))

            timestamp = f"2025-08-{index + 10:02d}T12:34:56Z"
            sensor = f"sensor-{secrets.token_hex(5)}"
            malformed = [
                f"timestamp,sensor_id,value,status\n{timestamp},{sensor},17.5\n",
                f"timestamp,sensor_id,value,status\n{timestamp},{sensor},17.5,OK,EXTRA\n",
                f'timestamp,sensor_id,value,status\n{timestamp},{sensor},"17.5\n18.5",OK\n',
            ][index % 3]
            evil_path = os.path.join(directory, secrets.token_hex(10) + ".bin")
            with open(evil_path, "w", newline="") as handle:
                handle.write(malformed)
            cases.append((evil_path, False))

        failures = []
        for path, expected_clean in cases:
            accepted = run_validator(path) == 0
            if accepted != expected_clean:
                failures.append((os.path.basename(path), expected_clean, accepted))

        assert not failures, f"Validator misclassified unseen CSV content: {failures}"


def invoke_process(content):
    script = "/home/user/process.sh"
    with tempfile.NamedTemporaryFile(mode="w", suffix=".csv", delete=False) as handle:
        handle.write(content)
        path = handle.name
    try:
        # Supply both the documented clean CSV path and stdin, accommodating either
        # conventional interpretation of "reads a clean CSV".
        result = subprocess.run(
            [script, path], input=content, capture_output=True, text=True, timeout=10
        )
        if not result.stdout.strip():
            result = subprocess.run(
                [script], input=content, capture_output=True, text=True, timeout=10
            )
        return result
    finally:
        os.remove(path)


def expected_sample(rows):
    seen = defaultdict(int)
    selected = []
    for row in rows:
        bucket = row[0][:13]
        if seen[bucket] < 2:
            selected.append(row)
        seen[bucket] += 1
    return selected


def assert_exact_process_output(content, expected):
    result = invoke_process(content)
    assert result.returncode == 0, f"process.sh failed: {result.stderr}"
    assert result.stdout.strip(), "process.sh produced no output"

    try:
        parsed = [row for row in csv.reader(io.StringIO(result.stdout)) if row]
    except csv.Error as exc:
        raise AssertionError(f"process.sh did not emit valid CSV: {exc}")

    if parsed and parsed[0] == HEADER:
        parsed = parsed[1:]
    assert HEADER not in parsed, "CSV header may only appear once at the beginning"
    assert all(len(row) == 4 for row in parsed), f"Output contains malformed rows: {parsed}"
    assert Counter(map(tuple, parsed)) == Counter(map(tuple, expected)), (
        f"Expected exactly the first two complete rows from each hour. "
        f"Expected {expected}, got {parsed}"
    )


def test_process_logic():
    rows = [
        ["2023-10-01T10:05:00Z", "1", "10.5", "ok"],
        ["2023-10-01T10:15:00Z", "2", "11.0", "ok"],
        ["2023-10-01T10:25:00Z", "3", "12.0", "ok"],
        ["2023-10-01T11:05:00Z", "1", "10.0", "ok"],
        ["2023-10-01T11:15:00Z", "2", "11.5", "ok"],
        ["2023-10-01T11:25:00Z", "3", "12.5", "ok"],
    ]
    stream = io.StringIO()
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(HEADER)
    writer.writerows(rows)
    result = invoke_process(stream.getvalue())
    assert result.returncode == 0, f"process.sh failed: {result.stderr}"

    output_lines = [line for line in result.stdout.strip().split("\n") if line]
    data_lines = [line for line in output_lines if "2023" in line]
    hour_10 = [line for line in data_lines if "T10:" in line]
    hour_11 = [line for line in data_lines if "T11:" in line]
    assert len(hour_10) == 2, f"Expected 2 rows for hour 10, got {len(hour_10)}"
    assert len(hour_11) == 2, f"Expected 2 rows for hour 11, got {len(hour_11)}"

    assert_exact_process_output(stream.getvalue(), expected_sample(rows))


def test_process_unseen_rows_and_buckets():
    for iteration in range(3):
        day = 10 + secrets.randbelow(15)
        hours = sorted({2 + secrets.randbelow(20) for _ in range(8)})[:3]
        while len(hours) < 3:
            candidate = 2 + secrets.randbelow(20)
            if candidate not in hours:
                hours.append(candidate)
                hours.sort()

        def make_row(hour, minute, sequence):
            return [
                f"2026-06-{day:02d}T{hour:02d}:{minute:02d}:{iteration:02d}Z",
                f"sensor-{secrets.token_hex(5)}-{sequence}",
                f"{secrets.randbelow(100000) / 100:.2f}",
                secrets.choice(["OK", "WARN", "READY"]),
            ]

        a, b, c = hours
        rows = [
            make_row(a, 47, 1),
            make_row(b, 3, 2),
            make_row(a, 5, 3),
            make_row(c, 51, 4),
            make_row(a, 22, 5),
            make_row(b, 58, 6),
            make_row(c, 7, 7),
            make_row(b, 19, 8),
            make_row(c, 33, 9),
        ]
        stream = io.StringIO()
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(HEADER)
        writer.writerows(rows)
        assert_exact_process_output(stream.getvalue(), expected_sample(rows))


def test_cron_setup():
    script_path = "/home/user/setup_cron.sh"

    # Ensure the result is installed by the script itself and specifically for user.
    subprocess.run(
        ["crontab", "-u", "user", "-r"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run([script_path], check=True, timeout=10)

    result = subprocess.run(
        ["crontab", "-u", "user", "-l"], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, "Crontab was not installed for user 'user'."

    cron_jobs = result.stdout.strip()
    assert "/home/user/pipeline.sh" in cron_jobs, "pipeline.sh is not in user user's crontab."

    import re
    assert re.search(
        r"^0\s+\*/4\s+\*\s+\*\s+\*.*\/home\/user\/pipeline\.sh",
        cron_jobs,
        re.MULTILINE,
    ), f"Crontab schedule is incorrect. Got: {cron_jobs}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
