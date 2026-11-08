#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import unicodedata
import uuid

SCRIPT = "/home/user/detect_spam.py"
INPUT = "/home/user/chat_stream.jsonl"
OUTPUT = "/home/user/flagged_messages.csv"


def normalize_text(text):
    text = text.lower()
    text = unicodedata.normalize('NFKD', text)
    return ''.join(c for c in text if c.isalnum() and c.isascii())


def get_bigrams(text):
    if len(text) < 2:
        return set()
    return set(text[i:i+2] for i in range(len(text)-1))


def jaccard_similarity(set1, set2):
    if not set1 and not set2:
        return 0.0
    intersection = len(set1.intersection(set2))
    union = len(set1.union(set2))
    return intersection / union if union > 0 else 0.0


def compute_expected_flags(input_file):
    window = []
    flagged = []

    with open(input_file, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            msg = json.loads(line)
            current_time = msg['timestamp']
            bigrams = get_bigrams(normalize_text(msg['text']))

            window = [m for m in window
                      if current_time - 60 < m['timestamp'] < current_time]

            best_match = None
            best_score = -1.0
            for w_msg in window:
                score = jaccard_similarity(bigrams, w_msg['bigrams'])
                if score >= 0.75:
                    if score > best_score:
                        best_score = score
                        best_match = w_msg
                    elif score == best_score:
                        if best_match is None or w_msg['timestamp'] < best_match['timestamp']:
                            best_match = w_msg

            if best_match:
                flagged.append({
                    'id': msg['id'],
                    'matched_id': best_match['id'],
                    'similarity_score': f"{best_score:.3f}"
                })

            window.append({
                'id': msg['id'],
                'timestamp': current_time,
                'bigrams': bigrams
            })

    return flagged


def assert_output_matches(input_file):
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist."
    assert os.path.isfile(OUTPUT), f"Path {OUTPUT} is not a file."

    expected_flags = compute_expected_flags(input_file)
    actual_flags = []
    with open(OUTPUT, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['id', 'matched_id', 'similarity_score'], \
            f"CSV headers are incorrect. Expected ['id', 'matched_id', 'similarity_score'], got {reader.fieldnames}"
        for row in reader:
            actual_flags.append(row)

    assert len(actual_flags) == len(expected_flags), \
        f"Expected {len(expected_flags)} flagged messages, but found {len(actual_flags)}."

    for i, (actual, expected) in enumerate(zip(actual_flags, expected_flags)):
        assert actual['id'] == expected['id'], \
            f"Row {i+1}: Expected id {expected['id']}, got {actual['id']}."
        assert actual['matched_id'] == expected['matched_id'], \
            f"Row {i+1} ({actual['id']}): Expected matched_id {expected['matched_id']}, got {actual['matched_id']}."
        assert actual['similarity_score'] == expected['similarity_score'], \
            f"Row {i+1} ({actual['id']}): Expected similarity_score {expected['similarity_score']}, got {actual['similarity_score']}."


def run_script():
    subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        check=True,
        timeout=30,
    )


def test_script_and_generated_csv():
    assert os.path.exists(SCRIPT), f"Required script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"Path {SCRIPT} is not a file."

    with open(INPUT, 'rb') as f:
        original_input = f.read()

    # Execute the submitted artifact and retain all original output assertions.
    run_script()
    assert_output_matches(INPUT)

    prefix = uuid.uuid4().hex
    records = [
        {'id': prefix + '_a', 'timestamp': 100, 'text': 'Café!!'},
        {'id': prefix + '_b', 'timestamp': 110, 'text': 'cafe'},
        {'id': prefix + '_c', 'timestamp': 120, 'text': 'ca-feX'},
        {'id': prefix + '_d', 'timestamp': 160, 'text': 'CAFÉ'},
        {'id': prefix + '_e', 'timestamp': 170, 'text': 'Z'},
        {'id': prefix + '_f', 'timestamp': 171, 'text': '!'},
        {'id': prefix + '_g', 'timestamp': 220, 'text': 'cafe'},
        {'id': prefix + '_h', 'timestamp': 221, 'text': 'café'},
    ]

    try:
        with open(INPUT, 'w', encoding='utf-8') as f:
            for record in records:
                f.write(json.dumps(record, ensure_ascii=False) + '\n')
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        run_script()
        assert_output_matches(INPUT)
    finally:
        with open(INPUT, 'wb') as f:
            f.write(original_input)
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        run_script()


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
