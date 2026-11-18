#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import random
import re
import secrets
import shutil
import subprocess
from pathlib import Path

SCRIPT = Path('/home/user/organize_datasets.sh')
RAW_DIR = Path('/home/user/raw_datasets')
PREDICTIONS = Path('/home/user/model_predictions.csv')
REPORT = Path('/home/user/validation_report.txt')


def run_script():
    if REPORT.exists():
        REPORT.unlink()
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', str(SCRIPT)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'Script exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert REPORT.is_file(), 'Script did not generate /home/user/validation_report.txt'


def test_00_execute_script_on_original_inputs():
    assert SCRIPT.is_file(), f'Script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'
    first_line = SCRIPT.read_text(errors='replace').splitlines()[0] if SCRIPT.stat().st_size else ''
    assert re.match(r'^#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+(?:-S\s+)?bash)(?:\s|$)', first_line), \
        'organize_datasets.sh must be an executable Bash script with a Bash shebang.'
    run_script()


def test_script_exists_and_executable():
    script_path = '/home/user/organize_datasets.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_report_exists():
    report_path = '/home/user/validation_report.txt'
    assert os.path.isfile(report_path), f"Report file {report_path} was not generated."


def test_report_content_invalid_datasets():
    report_path = '/home/user/validation_report.txt'
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."
    with open(report_path, 'r') as f:
        content = f.read()

    expected_line = "Invalid Datasets: dataset_3"
    assert re.search(r'^Invalid Datasets:\s*dataset_3$', content, re.MULTILINE), \
        f"Expected to find '{expected_line}' in {report_path}. Found:\n{content}"


def test_report_content_most_similar_pair():
    report_path = '/home/user/validation_report.txt'
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."
    with open(report_path, 'r') as f:
        content = f.read()

    expected_line = "Most Similar Pair: dataset_1, dataset_2"
    assert re.search(r'^Most Similar Pair:\s*dataset_1,\s*dataset_2$', content, re.MULTILINE), \
        f"Expected to find '{expected_line}' in {report_path}. Found:\n{content}"


def derive_expected(texts, prediction_rows):
    invalid = []
    for name, keywords in prediction_rows:
        lowered = texts[name].lower()
        hits = sum(keyword.lower() in lowered for keyword in keywords)
        if hits * 2 < len(keywords):
            invalid.append(name)

    word_sets = {
        name: set(re.findall(r'[A-Za-z0-9]+', text.lower()))
        for name, text in texts.items()
    }
    scored_pairs = []
    for left, right in itertools.combinations(sorted(texts), 2):
        scored_pairs.append((len(word_sets[left] & word_sets[right]), left, right))
    best_score = max(score for score, _, _ in scored_pairs)
    best_pairs = [(left, right) for score, left, right in scored_pairs if score == best_score]
    assert len(best_pairs) == 1, 'Verifier fixture must have a unique most-similar pair.'
    return sorted(invalid), best_pairs[0]


def test_pipeline_on_unseen_inputs():
    original_raw = {
        path.relative_to(RAW_DIR): path.read_bytes()
        for path in RAW_DIR.rglob('*') if path.is_file()
    }
    original_predictions = PREDICTIONS.read_bytes()

    names = [f'set_{secrets.token_hex(5)}' for _ in range(4)]
    while len(set(names)) != 4:
        names = [f'set_{secrets.token_hex(5)}' for _ in range(4)]
    tokens = [f't{secrets.token_hex(6)}' for _ in range(16)]

    texts = {
        names[0]: f'{tokens[0].upper()}, {tokens[1]}! {tokens[2]}; {tokens[3]} {tokens[4]} {tokens[0]}.',
        names[1]: f'{tokens[0]} {tokens[1].upper()} {tokens[2]} {tokens[3]} {tokens[4]} {tokens[5]}',
        names[2]: f'{tokens[0]} {tokens[6]}-{tokens[7]} {tokens[8]}',
        names[3]: f'{tokens[9]} {tokens[10]} {tokens[11]}',
    }
    prediction_rows = [
        (names[0], [tokens[0].upper(), tokens[1], tokens[12]]),
        (names[1], [tokens[2], tokens[3].upper(), tokens[13], tokens[14]]),
        (names[2], [tokens[6], tokens[12], tokens[15]]),
        (names[3], [tokens[9], tokens[12], tokens[13], tokens[14]]),
    ]
    random.SystemRandom().shuffle(prediction_rows)
    expected_invalid, expected_pair = derive_expected(texts, prediction_rows)

    try:
        shutil.rmtree(RAW_DIR)
        RAW_DIR.mkdir(mode=0o777)
        os.chmod(RAW_DIR, 0o777)
        for name, text in texts.items():
            (RAW_DIR / f'{name}.txt').write_text(text + '\n')
        PREDICTIONS.write_text(''.join(
            ','.join([name] + keywords) + '\n'
            for name, keywords in prediction_rows
        ))

        run_script()
        lines = REPORT.read_text().splitlines()
        expected_lines = [
            'Invalid Datasets: ' + ', '.join(expected_invalid),
            f'Most Similar Pair: {expected_pair[0]}, {expected_pair[1]}',
        ]
        assert lines == expected_lines, f'Expected report {expected_lines!r}, found {lines!r}'
    finally:
        shutil.rmtree(RAW_DIR, ignore_errors=True)
        RAW_DIR.mkdir(mode=0o777)
        os.chmod(RAW_DIR, 0o777)
        for relative, data in original_raw.items():
            destination = RAW_DIR / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        PREDICTIONS.write_bytes(original_predictions)
        run_script()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
