#!/bin/bash
mkdir -p /logs/verifier
passed=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import re
import pytest

def test_script_exists_and_executable():
    script_path = "/home/user/process_loc.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def process_data():
    en_path = "/home/user/loc_data/en_master.csv"
    fr_path = "/home/user/loc_data/fr_fr.txt"
    es_path = "/home/user/loc_data/es_es.txt"

    en_data = {}
    if os.path.exists(en_path):
        with open(en_path, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            for row in reader:
                if len(row) >= 2:
                    en_data[row[0]] = row[1]

    fr_data = {}
    if os.path.exists(fr_path):
        with open(fr_path, "r", encoding="iso-8859-1") as f:
            for line in f:
                m = re.match(r'\[(.*?)\]\s*=\s*"(.*?)"', line.strip())
                if m:
                    fr_data[m.group(1)] = m.group(2)

    es_data = {}
    if os.path.exists(es_path):
        with open(es_path, "r", encoding="utf-16le") as f:
            for line in f:
                m = re.match(r'Key:\s*(.*?)\s*\|\s*Val:\s*"(.*?)"', line.strip())
                if m:
                    es_data[m.group(1)] = m.group(2)

    merged = []
    for key in sorted(en_data.keys()):
        en_val = en_data.get(key, "")
        fr_val = fr_data.get(key, "")
        es_val = es_data.get(key, "")
        merged.append((key, en_val, fr_val, es_val))

    stats = []
    lengths = []
    for row in merged:
        key, _, fr_val, es_val = row
        l = len(fr_val) + len(es_val)
        lengths.append(l)

        window = lengths[-3:]
        avg = sum(window) / len(window)
        stats.append((key, round(avg, 1)))

    return merged, stats

def test_merged_translations():
    out_path = "/home/user/output/merged_translations.csv"
    assert os.path.isfile(out_path), f"Output file {out_path} does not exist."

    expected_merged, _ = process_data()

    actual_merged = []
    try:
        with open(out_path, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            assert header == ["Key", "EN", "FR", "ES"], f"Incorrect header in {out_path}"
            for row in reader:
                actual_merged.append(tuple(row))
    except UnicodeDecodeError:
        pytest.fail(f"Output file {out_path} is not valid UTF-8.")

    assert actual_merged == expected_merged, "Merged translations do not match the expected output format or data."

def test_stats():
    out_path = "/home/user/output/stats.csv"
    assert os.path.isfile(out_path), f"Output file {out_path} does not exist."

    _, expected_stats = process_data()

    actual_stats = []
    try:
        with open(out_path, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            assert header == ["Key", "RollingAvg"], f"Incorrect header in {out_path}"
            for row in reader:
                if len(row) >= 2:
                    actual_stats.append((row[0], float(row[1])))
    except UnicodeDecodeError:
        pytest.fail(f"Output file {out_path} is not valid UTF-8.")
    except ValueError:
        pytest.fail(f"Output file {out_path} contains invalid numeric values for RollingAvg.")

    assert len(actual_stats) == len(expected_stats), "Stats row count mismatch."
    for actual, expected in zip(actual_stats, expected_stats):
        assert actual[0] == expected[0], f"Key mismatch in stats: {actual[0]} != {expected[0]}"
        assert abs(actual[1] - expected[1]) < 0.05, f"Rolling average mismatch for key {actual[0]}: expected {expected[1]}, got {actual[1]}"
TEST_EOF

run_submission_and_tests() {
    rm -f /home/user/output/merged_translations.csv /home/user/output/stats.csv

    if [ -f /home/user/process_loc.sh ] && [ -x /home/user/process_loc.sh ] && \
       (cd /home/user && timeout 30 ./process_loc.sh); then
        :
    else
        passed=0
    fi

    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        :
    else
        passed=0
    fi
}

# Verify a clean execution against the original fixture.
run_submission_and_tests

# Replace the fixture with equivalent runtime-generated data so hardcoded output
# files or a script that merely recreates the known fixture cannot pass.
if python3 - <<'CHALLENGE_EOF'
import csv
import secrets

base = "/home/user/loc_data"
token = secrets.token_hex(8)

english = [
    ("APP_RETRY", f"Retry-{token}"),
    ("APP_GREETING", f"Welcome-{token}"),
    ("APP_HELP", f"Assistance-{token}"),
    ("APP_FAREWELL", f"Bye-{token}"),
    ("APP_ERROR", f"Failure-{token}"),
]
with open(f"{base}/en_master.csv", "w", encoding="utf-8", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["Key", "English"])
    writer.writerows(english)

fr_lines = [
    f'[APP_GREETING] = "Bonjour-{token}"',
    f'[APP_ERROR] = "Erreur-{token}"',
    f'[APP_HELP] = "Aide-{token}"',
]
with open(f"{base}/fr_fr.txt", "w", encoding="iso-8859-1", newline="") as f:
    f.write("\n".join(fr_lines) + "\n")

es_lines = [
    f'Key: APP_GREETING | Val: "Hola-{token}"',
    f'Key: APP_FAREWELL | Val: "Adiós-{token}"',
    f'Key: APP_RETRY | Val: "Reintentar-{token}"',
]
with open(f"{base}/es_es.txt", "w", encoding="utf-16le", newline="") as f:
    f.write("\n".join(es_lines) + "\n")
CHALLENGE_EOF
then
    run_submission_and_tests
else
    passed=0
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
