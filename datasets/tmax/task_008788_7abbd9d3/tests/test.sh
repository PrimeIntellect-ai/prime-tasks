#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import glob
import hashlib
import io
import os
import secrets
import stat
import subprocess

HOME = '/home/user'
RAW = os.path.join(HOME, 'raw_locales.csv')
SCRIPT = os.path.join(HOME, 'process.py')
WIDE = os.path.join(HOME, 'wide_locales.csv')


def expected_outputs(records):
    latest = {}
    for record in records:
        key = (record['msg_id'], record['locale'])
        previous = latest.get(key)
        if previous is None or record['timestamp'] > previous['timestamp']:
            latest[key] = dict(record)

    hash_groups = {}
    for record in latest.values():
        digest = hashlib.md5(record['translation'].encode('utf-8')).hexdigest()
        hash_groups.setdefault((record['locale'], digest), []).append(record)

    cleaned = []
    for group in hash_groups.values():
        cleaned.append(min(group, key=lambda record: record['msg_id']))

    locales = sorted({record['locale'] for record in cleaned})
    by_message = {}
    for record in cleaned:
        by_message.setdefault(record['msg_id'], {})[record['locale']] = record

    msg_ids = sorted(
        msg_id for msg_id, translations in by_message.items()
        if 'en' in translations
    )
    rows = [
        [msg_id] + [by_message[msg_id].get(locale, {}).get('translation', '') for locale in locales]
        for msg_id in msg_ids
    ]

    month_counts = {}
    for msg_id in msg_ids:
        month = by_message[msg_id]['en']['timestamp'][:7]
        month_counts[month] = month_counts.get(month, 0) + 1

    return ['msg_id'] + locales, rows, month_counts


def write_raw(records):
    with open(RAW, 'w', encoding='utf-8', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=['timestamp', 'msg_id', 'locale', 'translation'])
        writer.writeheader()
        writer.writerows(records)


def run_and_verify(records):
    expected_header, expected_rows, expected_months = expected_outputs(records)

    if os.path.exists(WIDE):
        os.remove(WIDE)
    for path in glob.glob(os.path.join(HOME, 'report_*.txt')):
        os.remove(path)

    completed = subprocess.run(
        ['python3', SCRIPT],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'process.py failed with exit code {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )

    assert os.path.isfile(WIDE), f'File {WIDE} is missing.'
    with open(WIDE, 'r', encoding='utf-8', newline='') as handle:
        actual = list(csv.reader(handle))

    assert actual, 'wide_locales.csv is empty.'
    assert actual[0] == expected_header, (
        f'Incorrect columns: expected {expected_header!r}, got {actual[0]!r}'
    )
    assert actual[0][0] == 'msg_id', "First column must be 'msg_id'."
    assert actual[0][1:] == sorted(actual[0][1:]), 'Locale columns must be sorted alphabetically.'
    assert actual[1:] == expected_rows, (
        f'Incorrect wide CSV rows. Expected {expected_rows!r}, got {actual[1:]!r}'
    )
    assert [row[0] for row in actual[1:]] == sorted(row[0] for row in actual[1:]), (
        'Rows must be sorted alphabetically by msg_id.'
    )
    assert all(len(row) == len(expected_header) for row in actual), (
        'wide_locales.csv contains extra or missing columns.'
    )

    expected_report_names = {f'report_{month}.txt' for month in expected_months}
    actual_report_names = {
        os.path.basename(path) for path in glob.glob(os.path.join(HOME, 'report_*.txt'))
    }
    assert actual_report_names == expected_report_names, (
        f'Incorrect report files: expected {sorted(expected_report_names)!r}, '
        f'got {sorted(actual_report_names)!r}'
    )

    for month, count in expected_months.items():
        path = os.path.join(HOME, f'report_{month}.txt')
        assert os.path.isfile(path), f'Report {path} is missing.'
        with open(path, 'r', encoding='utf-8', newline='') as handle:
            content = handle.read()
        expected_content = f'Month: {month}\nMessages: {count}'
        assert content in (expected_content, expected_content + '\n'), (
            f'Incorrect or extra content in {path}: {content!r}'
        )


def main():
    assert os.path.isfile(SCRIPT), f'Required script {SCRIPT} is missing.'
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} is not a regular file.'

    with open(RAW, 'rb') as handle:
        original_raw = handle.read()
    original_records = list(csv.DictReader(io.StringIO(original_raw.decode('utf-8'), newline='')))

    token = secrets.token_hex(8)
    a = f'a_{token}'
    b = f'b_{token}'
    c = f'c_{token}'
    orphan = f'z_{token}'
    shared_en = f'Shared English {token}\nwith newline'
    shared_es = f'Texto compartido {token}'
    generated_records = [
        {'timestamp': '2024-10-08T09:00:00', 'msg_id': b, 'locale': 'es', 'translation': f'Único {token}'},
        {'timestamp': '2024-09-01T00:00:00', 'msg_id': a, 'locale': 'en', 'translation': f'Old {token}'},
        {'timestamp': '2024-11-03T12:00:00', 'msg_id': c, 'locale': 'en', 'translation': f'Another {token}'},
        {'timestamp': '2024-10-07T09:00:00', 'msg_id': a, 'locale': 'es', 'translation': shared_es},
        {'timestamp': '2024-12-01T00:00:00', 'msg_id': orphan, 'locale': 'es', 'translation': f'Orphan {token}'},
        {'timestamp': '2024-10-05T11:00:00', 'msg_id': a, 'locale': 'en', 'translation': shared_en},
        {'timestamp': '2024-12-02T00:00:00', 'msg_id': b, 'locale': 'en', 'translation': shared_en},
        {'timestamp': '2024-11-03T12:05:00', 'msg_id': c, 'locale': 'es', 'translation': shared_es},
        {'timestamp': '2024-10-05T11:05:00', 'msg_id': a, 'locale': 'fr', 'translation': f'Bonjour {token}'},
        {'timestamp': '2024-11-03T12:10:00', 'msg_id': c, 'locale': 'fr', 'translation': f'Au revoir {token}'},
    ]

    try:
        # Exercise the submitted script on an unpredictable fixture, then rerun it
        # on the supplied fixture so all original expected behavior is also checked.
        write_raw(generated_records)
        run_and_verify(generated_records)
        write_raw(original_records)
        run_and_verify(original_records)
    finally:
        with open(RAW, 'wb') as handle:
            handle.write(original_raw)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
