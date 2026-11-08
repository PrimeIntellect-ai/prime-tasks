#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
from pathlib import Path

import pytest

INPUT = Path('/home/user/etl_data.tsv')
SCRIPT = Path('/home/user/clean_pipeline.sh')
CLEANED = Path('/home/user/cleaned_data.tsv')
REPORT = Path('/home/user/report.txt')


def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def get_expected_data(input_file='/home/user/etl_data.tsv'):
    if not os.path.exists(input_file):
        return [], 0, 0, 0

    records = []
    with open(input_file, 'r') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) >= 4:
                records.append({
                    'id': parts[0],
                    'category': parts[1],
                    'timestamp': int(parts[2]),
                    'message': parts[3],
                    'original': line
                })

    total_input = len(records)
    categories = {}
    for r in records:
        categories.setdefault(r['category'], []).append(r)

    kept_records = []
    for cat in sorted(categories.keys()):
        cat_records = sorted(categories[cat], key=lambda x: x['timestamp'])
        kept_for_cat = []
        for r in cat_records:
            is_duplicate = False
            for kept in kept_for_cat:
                if levenshtein(r['message'], kept['message']) <= 3:
                    is_duplicate = True
                    break
            if not is_duplicate:
                kept_for_cat.append(r)
                kept_records.append(r)

    total_cleaned = len(kept_records)
    total_dropped = total_input - total_cleaned
    return kept_records, total_input, total_cleaned, total_dropped


def assert_generated_outputs(input_file):
    expected_records, total_input, total_cleaned, total_dropped = get_expected_data(input_file)
    assert CLEANED.is_file(), f'{CLEANED} does not exist.'
    assert REPORT.is_file(), f'{REPORT} does not exist.'

    actual_lines = CLEANED.read_text().splitlines()
    expected_lines = [r['original'] for r in expected_records]
    assert actual_lines == expected_lines, (
        'cleaned_data.tsv does not preserve the complete original TSV records '
        'in the required category/timestamp order.'
    )

    expected_report = f'''=== ETL Deduplication Report ===
Total Input Records: {total_input}
Total Cleaned Records: {total_cleaned}
Total Duplicates Dropped: {total_dropped}
================================'''
    assert REPORT.read_text().strip() == expected_report


def run_pipeline():
    subprocess.run(
        [str(SCRIPT)], cwd='/home/user', check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )


def setup_module(module):
    assert SCRIPT.is_file(), f'{SCRIPT} does not exist or is not a regular file.'
    assert SCRIPT.stat().st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), (
        f'{SCRIPT} is not executable.'
    )

    original_input = INPUT.read_bytes()
    probe = (
        'p1\tZETA\t20\talpha\n'
        'p2\tALPHA\t30\tkitten\n'
        'p3\tALPHA\t10\tsitting\n'
        'p4\tALPHA\t20\twholly different\n'
        'p5\tZETA\t10\talpha!\n'
        'p6\tALPHA\t40\twholly diferent\n'
    ).encode()

    try:
        INPUT.write_bytes(probe)
        CLEANED.unlink(missing_ok=True)
        REPORT.unlink(missing_ok=True)
        run_pipeline()
        assert_generated_outputs(str(INPUT))
    finally:
        INPUT.write_bytes(original_input)
        CLEANED.unlink(missing_ok=True)
        REPORT.unlink(missing_ok=True)
        run_pipeline()


def test_cleaned_data():
    """Check IDs and the complete, ordered original TSV records."""
    assert CLEANED.exists(), f'{CLEANED} does not exist.'

    expected_records, _, _, _ = get_expected_data()
    expected_ids = {r['id'] for r in expected_records}

    actual_ids = []
    with CLEANED.open('r') as f:
        for line in f:
            line = line.strip()
            if line:
                actual_ids.append(line.split('\t')[0])

    assert set(actual_ids) == expected_ids, f'Cleaned data IDs {set(actual_ids)} do not match expected {expected_ids}.'
    assert len(actual_ids) == len(expected_ids), 'Cleaned data contains duplicates or incorrect number of records.'

    actual_lines = CLEANED.read_text().splitlines()
    expected_lines = [r['original'] for r in expected_records]
    assert actual_lines == expected_lines, 'Cleaned data is not the exact ordered TSV output.'
    assert all(len(line.split('\t')) == 4 for line in actual_lines), 'Each output record must have exactly four TSV fields.'


def test_report_content():
    """Check that report.txt contains the correct summary."""
    assert REPORT.exists(), f'{REPORT} does not exist.'

    _, total_input, total_cleaned, total_dropped = get_expected_data()
    expected_report = f'''=== ETL Deduplication Report ===
Total Input Records: {total_input}
Total Cleaned Records: {total_cleaned}
Total Duplicates Dropped: {total_dropped}
================================'''

    actual_report = REPORT.read_text().strip()
    assert actual_report == expected_report, 'Report content does not match the expected template and counts.'


def test_cron_scheduling():
    """Check that the user's crontab invokes the script at exactly 3:15 AM daily."""
    try:
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True, check=True)
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        crontab_content = ''

    if not crontab_content and os.path.exists('/var/spool/cron/crontabs/user'):
        with open('/var/spool/cron/crontabs/user', 'r') as f:
            crontab_content = f.read()

    assert '15 3 * * *' in crontab_content, "Cron schedule '15 3 * * *' not found in crontab."
    assert 'clean_pipeline.sh' in crontab_content, "Script 'clean_pipeline.sh' not found in crontab."

    try:
        user_cron = subprocess.run(
            ['crontab', '-u', 'user', '-l'], capture_output=True,
            text=True, check=True
        ).stdout
    except subprocess.CalledProcessError:
        user_cron = ''
    if not user_cron and os.path.exists('/var/spool/cron/crontabs/user'):
        user_cron = Path('/var/spool/cron/crontabs/user').read_text()

    valid = False
    for raw_line in user_cron.splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        fields = line.split(None, 5)
        if len(fields) != 6 or fields[:5] != ['15', '3', '*', '*', '*']:
            continue
        command = fields[5]
        if re.search(r'(^|[\s;&|])(?:/bin/bash\s+|/bin/sh\s+)?/home/user/clean_pipeline\.sh(?:$|[\s;&|])', command):
            valid = True
            break
    assert valid, 'No exact 3:15 AM daily user cron entry invokes /home/user/clean_pipeline.sh.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
