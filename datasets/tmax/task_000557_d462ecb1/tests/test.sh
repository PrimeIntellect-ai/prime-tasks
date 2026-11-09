#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
from pathlib import Path
import re
import secrets
import subprocess

SCRIPT = Path('/home/user/clean.sh')
RAW = Path('/home/user/raw_data.jsonl')
OUTPUT = Path('/home/user/clean_data.jsonl')


def write_jsonl(objects):
    RAW.write_text(
        ''.join(json.dumps(obj, ensure_ascii=True) + '\n' for obj in objects),
        encoding='utf-8'
    )


def run_script():
    if OUTPUT.exists():
        OUTPUT.unlink()
    env = os.environ.copy()
    env['TZ'] = 'UTC'
    result = subprocess.run(
        [str(SCRIPT)],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'clean.sh exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def read_output():
    assert os.path.isfile(OUTPUT), f'{OUTPUT} does not exist.'
    objects = []
    with OUTPUT.open('r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                objects.append(json.loads(line))
            except json.JSONDecodeError:
                assert False, f'Invalid JSON found in {OUTPUT}: {line}'
    return objects


def test_complete_cleaning_workflow():
    # Preserve the original artifact assertions.
    assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'{SCRIPT} is not executable.'

    first_line = SCRIPT.read_text(encoding='utf-8', errors='replace').splitlines()[0]
    assert re.match(
        r'^#!\s*(?:/usr/bin/env(?:\s+-S)?\s+)?(?:/bin/bash|/usr/bin/bash|bash)(?:\s|$)',
        first_line,
    ), 'clean.sh must be a Bash script with a Bash shebang.'

    original_input = [
        {'User_Name': 'José', 'Email': 'jose123@gmail.com', 'TIMESTAMP': '1672531200', 'Message': 'Hello'},
        {'user_name': 'Müller', 'email': 'muller.tech@company.org', 'timestamp': '2023-01-02 15:30:00', 'message': 'Test'},
        {'USER_NAME': 'テスト', 'email': 'admin@localhost.local', 'timestamp': '1672765200', 'message': 'System startup'},
        {'Name': 'François', 'eMail': 'francois_99@sub.domain.co.uk', 'Timestamp': '2023-10-31 08:15:45', 'Notes': 'None'},
    ]
    expected_objects = [
        {'email': '***@gmail.com', 'email_domain': 'gmail.com', 'message': 'Hello', 'timestamp': '2023-01-01T00:00:00Z', 'user_name': 'José'},
        {'email': '***@company.org', 'email_domain': 'company.org', 'message': 'Test', 'timestamp': '2023-01-02T15:30:00Z', 'user_name': 'Müller'},
        {'email': '***@localhost.local', 'email_domain': 'localhost.local', 'message': 'System startup', 'timestamp': '2023-01-03T17:00:00Z', 'user_name': 'テスト'},
        {'email': '***@sub.domain.co.uk', 'email_domain': 'sub.domain.co.uk', 'name': 'François', 'notes': 'None', 'timestamp': '2023-10-31T08:15:45Z'},
    ]

    write_jsonl(original_input)
    run_script()
    assert os.path.isfile(OUTPUT), f'{OUTPUT} does not exist.'
    actual_objects = read_output()
    assert len(actual_objects) == len(expected_objects), (
        f'Expected {len(expected_objects)} JSON objects, found {len(actual_objects)}.'
    )
    for i, (expected, actual) in enumerate(zip(expected_objects, actual_objects)):
        assert actual == expected, (
            f'Object at line {i + 1} does not match expected output.\n'
            f'Expected: {expected}\nActual: {actual}'
        )

    # Execute the submitted script again on unpredictable inputs so a fixed output
    # file or script which only emits the four known records cannot pass.
    token = secrets.token_hex(6)
    epoch = 1700000000 + secrets.randbelow(5000000)
    epoch_iso = datetime.datetime.fromtimestamp(
        epoch, tz=datetime.timezone.utc
    ).strftime('%Y-%m-%dT%H:%M:%SZ')
    minute = secrets.randbelow(60)
    second = secrets.randbelow(60)
    text_timestamp = f'2031-07-19 11:{minute:02d}:{second:02d}'
    text_iso = f'2031-07-19T11:{minute:02d}:{second:02d}Z'
    domain1 = f'{token}.example.net'
    domain2 = f'sub-{token}.example.org'

    dynamic_input = [
        {
            'UsEr_NaMe': f'Zoë-{token}',
            'EMAIL': f'person+{token}@{domain1}',
            'TimeStamp': str(epoch),
            'MeSsAgE': f'café-{token}',
            'Extra_Field': 'naïve',
        },
        {
            'NAME': f'李-{token}',
            'eMaIl': f'other.{token}@{domain2}',
            'TIMESTAMP': text_timestamp,
            'NOTES': 'résumé',
        },
    ]
    dynamic_expected = [
        {
            'user_name': f'Zoë-{token}',
            'email': f'***@{domain1}',
            'timestamp': epoch_iso,
            'message': f'café-{token}',
            'extra_field': 'naïve',
            'email_domain': domain1,
        },
        {
            'name': f'李-{token}',
            'email': f'***@{domain2}',
            'timestamp': text_iso,
            'notes': 'résumé',
            'email_domain': domain2,
        },
    ]

    write_jsonl(dynamic_input)
    run_script()
    dynamic_actual = read_output()
    assert dynamic_actual == dynamic_expected, (
        f'clean.sh failed on generated input.\n'
        f'Expected: {dynamic_expected}\nActual: {dynamic_actual}'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
