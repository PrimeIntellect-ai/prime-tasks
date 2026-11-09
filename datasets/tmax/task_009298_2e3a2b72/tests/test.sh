#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import hashlib
import statistics

def test_flagged_translations_exists():
    assert os.path.exists("/home/user/flagged_translations.txt"), "The output file /home/user/flagged_translations.txt does not exist."
    assert os.path.isfile("/home/user/flagged_translations.txt"), "/home/user/flagged_translations.txt is not a file."

def test_flagged_translations_correct():
    input_file = "/home/user/tm_updates.jsonl"
    output_file = "/home/user/flagged_translations.txt"

    assert os.path.exists(input_file), f"Input file {input_file} is missing."

    # Recompute the expected result
    data = []
    with open(input_file, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                data.append(json.loads(line))

    dedup = {}
    for d in data:
        key_str = f"{d['source_lang']}_|{d['target_lang']}_|{d['source_text']}"
        key = hashlib.md5(key_str.encode('utf-8')).hexdigest()
        if key not in dedup or d['timestamp'] > dedup[key]['timestamp']:
            dedup[key] = d

    filtered = [v for v in dedup.values() if v['source_lang'] == 'en' and v['target_lang'] == 'fr']
    filtered.sort(key=lambda x: x['timestamp'])

    expected_anomalies = []
    ratios = []
    for d in filtered:
        r = len(d['target_text']) / len(d['source_text'])

        if len(ratios) >= 10:
            window = ratios[-30:]
            mu = statistics.mean(window)
            s = statistics.stdev(window)

            if abs(r - mu) > 3 * s:
                expected_anomalies.append(d['id'])

        ratios.append(r)

    # Read actual result
    with open(output_file, "r", encoding="utf-8") as f:
        actual_anomalies = [line.strip() for line in f if line.strip()]

    assert actual_anomalies == expected_anomalies, (
        f"The flagged anomalies do not match the expected output.\n"
        f"Expected: {expected_anomalies}\n"
        f"Actual: {actual_anomalies}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
