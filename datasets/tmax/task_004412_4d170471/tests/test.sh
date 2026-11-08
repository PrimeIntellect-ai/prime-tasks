#!/bin/bash
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import hashlib
import csv
import pytest

def get_expected_data():
    log_dir = "/home/user/raw_logs"
    pattern = re.compile(r'\[(.*?)\] INFO Extracted translation -> Key: (.*?) \| Lang: (.*?) \| Value: (.*)')

    entries = {}
    counts = {}

    if not os.path.exists(log_dir):
        return [], []

    for filename in os.listdir(log_dir):
        if not filename.endswith('.log'):
            continue
        filepath = os.path.join(log_dir, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                match = pattern.search(line)
                if match:
                    ts, key, lang, value = match.groups()
                    key_lang = f"{key}_{lang}"

                    if key_lang not in entries:
                        entries[key_lang] = (ts, value)
                        counts[key_lang] = 1
                    else:
                        counts[key_lang] += 1
                        if ts > entries[key_lang][0]:
                            entries[key_lang] = (ts, value)

    final_csv = [["Key", "Lang", "Value"]]
    for key_lang in sorted(entries.keys()):
        key, lang = key_lang.split('_', 1)
        final_csv.append([key, lang, entries[key_lang][1]])

    duplicates = []
    for key_lang, count in counts.items():
        if count > 1:
            md5 = hashlib.md5(key_lang.encode('utf-8')).hexdigest()
            duplicates.append(md5)

    return final_csv, sorted(duplicates)

def test_script_exists():
    script_path = "/home/user/process_locales.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

def test_final_csv_output():
    csv_path = "/home/user/locales/final.csv"
    assert os.path.isfile(csv_path), f"The output file {csv_path} does not exist."

    expected_csv, _ = get_expected_data()

    actual_csv = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_csv.append(row)

    assert actual_csv == expected_csv, "The contents of final.csv do not match the expected deduplicated and sorted output."

def test_duplicate_report_output():
    report_path = "/home/user/locales/duplicate_report.txt"
    assert os.path.isfile(report_path), f"The output file {report_path} does not exist."

    _, expected_duplicates = get_expected_data()

    with open(report_path, 'r', encoding='utf-8') as f:
        actual_duplicates = [line.strip() for line in f if line.strip()]

    assert actual_duplicates == expected_duplicates, "The contents of duplicate_report.txt do not match the expected MD5 hashes."
TEST_EOF

# Preserve the original final-state assertions for the logs supplied to the agent.
if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    exit 0
fi

# Replace the inputs with an unpredictable second data set, remove all compiled
# output, and require the submitted script itself to regenerate it.
rm -rf /home/user/raw_logs /home/user/locales
mkdir -p /home/user/raw_logs

if ! python3 << 'CHALLENGE_EOF'
import os
import secrets

token = secrets.token_hex(6).upper()
key_a = "ALPHA" + token
key_m = "MIDDLE" + token
key_z = "ZULU" + token

logs = {
    "run17.log": f"""[2025-02-01T08:00:00] DEBUG Starting extraction
[2025-02-01T08:01:00] INFO Extracted translation -> Key: {key_z} | Lang: fr | Value: Ancien
[2025-02-01T08:02:00] INFO Extracted translation -> Key: {key_a} | Lang: en | Value: Stable{token}
[2025-02-01T08:03:00] INFO Extracted translation -> Key: {key_z} | Lang: de | Value: Eintrag{token}
""",
    "run42.log": f"""[2025-02-03T10:00:00] DEBUG Retrying extraction
[2025-02-03T10:01:00] INFO Extracted translation -> Key: {key_z} | Lang: fr | Value: Nouveau{token}
[2025-02-03T10:02:00] INFO Extracted translation -> Key: {key_a} | Lang: en | Value: Stable{token}
[2025-02-03T10:03:00] INFO Extracted translation -> Key: {key_m} | Lang: es | Value: Valor{token}
""",
    # This file is encountered after run42 by many implementations, but its
    # duplicate is older, so resolution must use the timestamp rather than
    # simply the last input record.
    "run99.log": f"""[2025-02-02T09:00:00] INFO Extracted translation -> Key: {key_z} | Lang: fr | Value: Intermedia
[2025-02-02T09:01:00] WARN Retry completed
""",
}

for name, contents in logs.items():
    with open(os.path.join("/home/user/raw_logs", name), "w", encoding="utf-8") as f:
        f.write(contents)

# A matching-looking line outside a .log file must not be processed.
with open("/home/user/raw_logs/ignored.txt", "w", encoding="utf-8") as f:
    f.write(f"[2099-01-01T00:00:00] INFO Extracted translation -> Key: {key_z} | Lang: fr | Value: Wrong\n")
CHALLENGE_EOF
then
    exit 0
fi

chown -R user:user /home/user/raw_logs

if ! su -s /bin/bash user -c 'bash /home/user/process_locales.sh'; then
    exit 0
fi

# Reuse the original behavioral assertions, now deriving expectations from the
# changed inputs and checking the files produced by the submitted script.
if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    exit 0
fi

reward=1
exit 0
