#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import csv
import shutil
import secrets
from collections import Counter, defaultdict

SCRIPT_PATH = "/home/user/process_loc.sh"
INPUT_PATH = "/home/user/incoming/loc_drops.csv"
OUTPUT_DIR = "/home/user/output"
CLEANED_PATH = os.path.join(OUTPUT_DIR, "cleaned.csv")
STATS_PATH = os.path.join(OUTPUT_DIR, "cumulative_stats.csv")


def run_script():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"


def read_csv(path):
    with open(path, "r", newline="") as f:
        return list(csv.reader(f))


def test_script_exists_and_executable():
    script_path = "/home/user/process_loc.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_run_script():
    # Execute the script to ensure it produces the expected output
    result = subprocess.run(["/home/user/process_loc.sh"], capture_output=True, text=True)
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"


def test_cleaned_csv():
    cleaned_path = "/home/user/output/cleaned.csv"
    assert os.path.isfile(cleaned_path), f"File {cleaned_path} does not exist."

    expected_rows = [
        ["T001", "es", "1696204800", "carlos@anonymized.local", "150"],
        ["T002", "fr", "1696204900", "marie@anonymized.local", "200"],
        ["T004", "es", "1696291200", "luis@anonymized.local", "300"],
        ["T005", "fr", "1696291200", "luc@anonymized.local", "110"],
        ["T003", "de", "1696291500", "hans@anonymized.local", "95"]
    ]

    with open(cleaned_path, "r") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    expected_sorted = sorted(expected_rows, key=lambda x: int(x[2]))
    actual_sorted = sorted(actual_rows, key=lambda x: int(x[2]))

    assert actual_rows == actual_sorted, "cleaned.csv is not sorted by timestamp in ascending order."
    assert len(actual_rows) == len(expected_rows), "cleaned.csv does not have the correct number of rows."

    for row in expected_rows:
        assert row in actual_rows, f"Expected row {row} not found in cleaned.csv."


def test_cumulative_stats_csv():
    stats_path = "/home/user/output/cumulative_stats.csv"
    assert os.path.isfile(stats_path), f"File {stats_path} does not exist."

    expected_rows = [
        ["1696204800", "es", "150"],
        ["1696204900", "fr", "200"],
        ["1696291200", "es", "450"],
        ["1696291200", "fr", "310"],
        ["1696291500", "de", "95"]
    ]

    with open(stats_path, "r") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    actual_sorted = sorted(actual_rows, key=lambda x: int(x[0]))
    assert actual_rows == actual_sorted, "cumulative_stats.csv is not sorted by timestamp in ascending order."
    assert len(actual_rows) == len(expected_rows), "cumulative_stats.csv does not have the correct number of rows."

    for row in expected_rows:
        assert row in actual_rows, f"Expected row {row} not found in cumulative_stats.csv."


def test_cron_job():
    # Check if crontab contains the expected job
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."

    cron_lines = [line.strip() for line in result.stdout.split('\n') if line.strip() and not line.startswith('#')]

    expected_command = "/home/user/process_loc.sh"
    found = False
    for line in cron_lines:
        parts = line.split()
        if len(parts) >= 6:
            minute, hour, dom, mon, dow = parts[:5]
            command = " ".join(parts[5:])
            if minute == "15" and hour == "3" and dom == "*" and mon == "*" and dow == "*" and expected_command in command:
                found = True
                break

    assert found, "Cron job for /home/user/process_loc.sh at 03:15 AM is not set correctly."


def expected_for(rows):
    latest = {}
    for row in rows:
        key = (row[0], row[1])
        if key not in latest or int(row[2]) > int(latest[key][2]):
            latest[key] = row[:]

    cleaned = []
    for row in latest.values():
        masked = row[:]
        masked[3] = masked[3].split("@", 1)[0] + "@anonymized.local"
        cleaned.append(masked)

    grouped = defaultdict(int)
    for row in latest.values():
        grouped[(int(row[2]), row[1])] += int(row[4])

    cumulative = defaultdict(int)
    stats = []
    for timestamp, language in sorted(grouped, key=lambda key: (key[0], key[1])):
        cumulative[language] += grouped[(timestamp, language)]
        stats.append([str(timestamp), language, str(cumulative[language])])

    return cleaned, stats


def verify_dynamic_output(rows):
    expected_cleaned, expected_stats = expected_for(rows)

    assert os.path.isfile(CLEANED_PATH), f"File {CLEANED_PATH} does not exist."
    assert os.path.isfile(STATS_PATH), f"File {STATS_PATH} does not exist."

    actual_cleaned = read_csv(CLEANED_PATH)
    assert all(len(row) == 5 for row in actual_cleaned), "cleaned.csv must have exactly five columns per row."
    assert [int(row[2]) for row in actual_cleaned] == sorted(int(row[2]) for row in actual_cleaned), \
        "cleaned.csv is not sorted numerically by timestamp."
    assert Counter(map(tuple, actual_cleaned)) == Counter(map(tuple, expected_cleaned)), \
        "cleaned.csv does not correctly deduplicate and anonymize the modified input."

    actual_stats = read_csv(STATS_PATH)
    assert all(len(row) == 3 for row in actual_stats), "cumulative_stats.csv must have exactly three columns per row."
    assert [int(row[0]) for row in actual_stats] == sorted(int(row[0]) for row in actual_stats), \
        "cumulative_stats.csv is not sorted numerically by timestamp."
    assert Counter(map(tuple, actual_stats)) == Counter(map(tuple, expected_stats)), \
        "cumulative_stats.csv is incorrect for the modified input."


def install_input(rows):
    with open(INPUT_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerows(rows)


def test_pipeline_reads_changed_input_and_is_idempotent():
    token = secrets.token_hex(8)
    base = secrets.randbelow(500000) + 1800000000

    rows_one = [
        [f"old-{token}", "es", str(base + 2), f"first+tag@old-{token}.example", "17"],
        [f"fr-a-{token}", "fr", str(base + 40), f"anne@domain-{token}.fr", "31"],
        [f"old-{token}", "es", str(base + 100), f"winner@new-{token}.example", "23"],
        [f"es-b-{token}", "es", str(base + 40), f"beta@private-{token}.net", "11"],
        [f"fr-b-{token}", "fr", str(base + 40), f"charlie@other-{token}.org", "7"],
        [f"de-a-{token}", "de", str(base + 9), f"dora@secret-{token}.de", "5"],
        [f"de-b-{token}", "de", str(base + 140), f"emil@secret-{token}.de", "13"],
        [f"fr-a-{token}", "fr", str(base + 1), f"discard@obsolete-{token}.com", "999"]
    ]

    shutil.rmtree(OUTPUT_DIR, ignore_errors=True)
    install_input(rows_one)
    run_script()
    verify_dynamic_output(rows_one)

    with open(CLEANED_PATH, "rb") as f:
        first_cleaned = f.read()
    with open(STATS_PATH, "rb") as f:
        first_stats = f.read()

    run_script()
    verify_dynamic_output(rows_one)
    with open(CLEANED_PATH, "rb") as f:
        assert f.read() == first_cleaned, "A retry changed or appended to cleaned.csv."
    with open(STATS_PATH, "rb") as f:
        assert f.read() == first_stats, "A retry changed or appended to cumulative_stats.csv."

    rows_two = [
        [f"new-a-{token}", "ja", str(base + 1003), f"one@dynamic-{token}.jp", "41"],
        [f"new-a-{token}", "ja", str(base + 1001), f"stale@dynamic-{token}.jp", "800"],
        [f"new-b-{token}", "ja", str(base + 1003), f"two@another-{token}.jp", "19"],
        [f"new-c-{token}", "it", str(base + 7), f"three@dynamic-{token}.it", "29"],
        [f"new-d-{token}", "it", str(base + 1200), f"four@dynamic-{token}.it", "3"]
    ]

    install_input(rows_two)
    run_script()
    verify_dynamic_output(rows_two)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
