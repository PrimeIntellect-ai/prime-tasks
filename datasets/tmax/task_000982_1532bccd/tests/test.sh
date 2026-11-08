#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import re
import subprocess
from collections import Counter

def test_pipeline_script_exists_and_executable():
    path = "/home/user/pipeline.sh"
    assert os.path.isfile(path), f"Missing file: {path}"
    assert os.access(path, os.X_OK), f"Script {path} is not executable"

def test_pipeline_script_generates_report():
    script_path = "/home/user/pipeline.sh"
    report_path = "/home/user/report.csv"
    assert os.path.isfile(script_path), f"Missing file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    # Remove any precomputed report so the submitted script must generate it.
    if os.path.exists(report_path):
        os.remove(report_path)

    result = subprocess.run(
        [script_path],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}. "
        f"stdout: {result.stdout!r} stderr: {result.stderr!r}"
    )
    assert os.path.isfile(report_path), "pipeline.sh did not generate /home/user/report.csv"

def test_report_csv_exists():
    path = "/home/user/report.csv"
    assert os.path.isfile(path), f"Missing file: {path}"

def get_expected_report():
    reviews_path = "/home/user/reviews.csv"
    stopwords_path = "/home/user/stopwords.txt"
    seed_path = "/home/user/random_seed.dat"

    with open(stopwords_path, 'r') as f:
        stopwords = set(line.strip().lower() for line in f)

    reviews = []
    with open(reviews_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            reviews.append(row)

    word_counts = Counter()
    for row in reviews:
        text = row['text'].lower()
        text = re.sub(r'[^a-z]', ' ', text)
        words = text.split()
        for w in words:
            if len(w) >= 3 and w not in stopwords:
                word_counts[w] += 1

    # Sort by frequency (desc), then alphabetically
    sorted_words = sorted(word_counts.items(), key=lambda x: (-x[1], x[0]))
    top_3_words = [w[0] for w in sorted_words[:3]]
    top_3_words.sort()

    # Prepare data for shuf
    data_lines = []
    with open(reviews_path, 'r') as f:
        lines = f.read().splitlines()
        header = lines[0]
        data_lines = lines[1:]

    data_str = "\n".join(data_lines) + "\n"

    expected_results = []

    # Run shuf 3 times. Since it's run as separate commands, it reads from the start of the seed file each time,
    # meaning the samples will actually be identical. We'll replicate exactly what the bash script would do.
    for sample_id in range(1, 4):
        cmd = ["shuf", "-r", "-n", str(len(data_lines)), f"--random-source={seed_path}"]
        res = subprocess.run(cmd, input=data_str, text=True, capture_output=True, check=True)
        sampled_lines = res.stdout.strip().split('\n')

        sampled_reviews = []
        for line in sampled_lines:
            if not line:
                continue
            parts = line.split(',', 2)
            if len(parts) == 3:
                sampled_reviews.append({'rating': int(parts[1]), 'text': parts[2]})

        for word in top_3_words:
            ratings = []
            for row in sampled_reviews:
                text = row['text'].lower()
                text = re.sub(r'[^a-z]', ' ', text)
                words = text.split()
                if word in words:
                    ratings.append(row['rating'])

            avg = sum(ratings) / len(ratings) if ratings else 0.0
            expected_results.append((sample_id, word, f"{avg:.2f}"))

    # Sort by Sample_ID, then Word
    expected_results.sort(key=lambda x: (x[0], x[1]))
    return expected_results

def test_report_csv_content():
    path = "/home/user/report.csv"
    assert os.path.isfile(path), f"Missing file: {path}"

    expected = get_expected_report()

    actual = []
    with open(path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["Sample_ID", "Word", "Average_Rating"], "Incorrect CSV header"
        for row in reader:
            if row:
                actual.append((int(row[0]), row[1], row[2]))

    assert len(actual) == len(expected), f"Expected {len(expected)} rows, got {len(actual)}"

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act == exp, f"Row {i+1} mismatch: expected {exp}, got {act}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
