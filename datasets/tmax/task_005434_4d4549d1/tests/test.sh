#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

ANALYZE = '/home/user/analyze.py'
DESCRIPTIONS = '/home/user/descriptions.txt'
TOP_PAIR = '/home/user/top_pair.txt'
TIME_LOG = '/home/user/time.log'
REPRO_SCRIPT = '/home/user/test_reproducibility.sh'
REPRO_RESULT = '/home/user/repro_result.txt'


def trigrams(text):
    text = text.lower()
    return {text[i:i + 3] for i in range(len(text) - 2)}


def load_descriptions(path=DESCRIPTIONS):
    rows = []
    with open(path, 'r') as f:
        for line in f:
            line = line.rstrip('\n')
            dataset_id, text = line.split('|', 1)
            rows.append((dataset_id, text))
    return rows


def similarity(a, b):
    left = trigrams(a)
    right = trigrams(b)
    union = left | right
    return len(left & right) / len(union) if union else 0.0


def validate_outputs(rows):
    assert os.path.isfile(TOP_PAIR), f"Missing file: {TOP_PAIR}"
    with open(TOP_PAIR, 'r') as f:
        content = f.read().strip()

    match = re.fullmatch(r'([^,\n]+),([^,\n]+),(\d+\.\d{4})', content)
    assert match, f"Incorrect format in {TOP_PAIR}: '{content}'"
    id1, id2, score_text = match.groups()
    assert id1 < id2, "ID1 must be alphabetically before ID2"

    descriptions = dict(rows)
    assert id1 in descriptions and id2 in descriptions, "Reported IDs are not in the input"

    all_scores = []
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            all_scores.append(similarity(rows[i][1], rows[j][1]))
    expected_max = max(all_scores)
    reported_similarity = similarity(descriptions[id1], descriptions[id2])

    assert abs(reported_similarity - expected_max) < 1e-12, (
        f"Reported pair is not a highest-similarity pair: {content}"
    )
    assert score_text == f"{reported_similarity:.4f}", (
        f"Incorrect rounded score for reported pair: {score_text}"
    )

    assert os.path.isfile(TIME_LOG), f"Missing file: {TIME_LOG}"
    with open(TIME_LOG, 'r') as f:
        time_content = f.read().strip()
    try:
        time_value = float(time_content)
    except ValueError:
        assert False, f"Content of {TIME_LOG} is not a valid float: '{time_content}'"
    assert math.isfinite(time_value) and time_value >= 0, (
        f"Time value in {TIME_LOG} must be a finite non-negative float, got {time_content}"
    )


def run_analyze_and_validate(rows):
    result = subprocess.run(['python3', ANALYZE], capture_output=True, text=True)
    assert result.returncode == 0, f"analyze.py failed: {result.stderr}"
    validate_outputs(rows)


def run_repro_with_instrumented_analyze(mode, expected_result):
    counter = '/tmp/analyze_run_count'
    if os.path.exists(counter):
        os.remove(counter)

    wrapper = '''import os
counter = "/tmp/analyze_run_count"
try:
    with open(counter, "r") as f:
        n = int(f.read())
except (FileNotFoundError, ValueError):
    n = 0
n += 1
with open(counter, "w") as f:
    f.write(str(n))
mode = os.environ.get("REPRO_TEST_MODE", "same")
value = "A,B,1.0000" if mode == "same" else f"A,B,0.000{n}"
with open("/home/user/top_pair.txt", "w") as f:
    f.write(value + "\\n")
with open("/home/user/time.log", "w") as f:
    f.write("0.0\\n")
'''
    with open(ANALYZE, 'w') as f:
        f.write(wrapper)

    env = os.environ.copy()
    env['REPRO_TEST_MODE'] = mode
    subprocess.run(['bash', REPRO_SCRIPT], env=env, capture_output=True, text=True)

    assert os.path.isfile(counter), "Reproducibility script did not run analyze.py"
    with open(counter, 'r') as f:
        count = int(f.read())
    assert count == 3, f"Reproducibility script must run analyze.py three times, ran it {count} times"

    assert os.path.isfile(REPRO_RESULT), f"Missing file: {REPRO_RESULT}"
    with open(REPRO_RESULT, 'r') as f:
        result = f.read().strip()
    assert result == expected_result, (
        f"Expected reproducibility result {expected_result}, got {result}"
    )


def test_complete_pipeline():
    assert os.path.isfile(ANALYZE), f"Missing script: {ANALYZE}"
    assert os.path.isfile(REPRO_SCRIPT), f"Missing script: {REPRO_SCRIPT}"
    mode = os.stat(REPRO_SCRIPT).st_mode
    assert bool(mode & stat.S_IXUSR), f"Script {REPRO_SCRIPT} is not executable"

    with open(ANALYZE, 'rb') as f:
        original_analyze = f.read()
    analyze_mode = os.stat(ANALYZE).st_mode
    with open(DESCRIPTIONS, 'rb') as f:
        original_descriptions = f.read()

    original_rows = load_descriptions()

    try:
        # Execute the submitted analyzer on the supplied data and derive the
        # correct maximum from that data, allowing any genuinely maximal tie.
        run_analyze_and_validate(original_rows)

        # Exercise case folding, spaces, punctuation, arbitrary IDs, and a
        # maximum that is unrelated to the formerly hard-coded D998/D999 pair.
        controlled = [
            ('ZETA', 'A b!'),
            ('ALPHA', 'a B?'),
            ('OMEGA', 'completely unrelated text'),
            ('BETA', 'COMPLETELY unrelated tex!'),
            ('GAMMA', '123 punctuation, spaces.'),
        ]
        with open(DESCRIPTIONS, 'w') as f:
            for dataset_id, text in controlled:
                f.write(f'{dataset_id}|{text}\n')
        run_analyze_and_validate(controlled)

        # Restore the supplied input before testing the bash pipeline.
        with open(DESCRIPTIONS, 'wb') as f:
            f.write(original_descriptions)

        # Verify that the reproducibility script really performs three runs,
        # hashes their outputs, and distinguishes stable from changing output.
        run_repro_with_instrumented_analyze('same', 'PASS')
        run_repro_with_instrumented_analyze('different', 'FAIL')
    finally:
        with open(ANALYZE, 'wb') as f:
            f.write(original_analyze)
        os.chmod(ANALYZE, analyze_mode)
        with open(DESCRIPTIONS, 'wb') as f:
            f.write(original_descriptions)

    # Execute the real submitted reproducibility pipeline and validate its
    # final artifacts against the supplied input.
    result = subprocess.run(['bash', REPRO_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"Reproducibility script failed: {result.stderr}"
    validate_outputs(original_rows)
    assert os.path.isfile(REPRO_RESULT), f"Missing file: {REPRO_RESULT}"
    with open(REPRO_RESULT, 'r') as f:
        repro_content = f.read().strip()
    assert repro_content == 'PASS', (
        f"Incorrect content in {REPRO_RESULT}. Expected 'PASS', got '{repro_content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
