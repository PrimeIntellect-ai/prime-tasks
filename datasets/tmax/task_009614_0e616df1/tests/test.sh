#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
from collections import defaultdict
from decimal import Decimal
from pathlib import Path

SCRIPT = Path('/home/user/build_model.sh')
CSV_PATH = Path('/home/user/raw_logs.csv')
JSON_PATH = Path('/home/user/item_probs.json')


def expected_from_csv(path):
    user_items = defaultdict(set)
    item_users = defaultdict(set)
    with open(path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['action_type'] == 'purchase':
                user_items[row['user_id']].add(row['item_id'])
                item_users[row['item_id']].add(row['user_id'])

    expected = {}
    for x in item_users:
        x_users = item_users[x]
        y_counts = defaultdict(int)
        for user in x_users:
            for y in user_items[user]:
                if y != x:
                    y_counts[y] += 1
        values = [
            {'item': y, 'prob': round(count / len(x_users), 2)}
            for y, count in y_counts.items()
        ]
        values.sort(key=lambda entry: (-entry['prob'], entry['item']))
        expected[x] = values
    return expected


def load_and_validate(path, expected):
    number_pattern = re.compile(r'^(?:0|[1-9][0-9]*)\.[0-9]{2}$')

    def parse_float(token):
        assert number_pattern.fullmatch(token), \
            f'Probability {token!r} is not written with exactly two decimal places.'
        return Decimal(token)

    def reject_integer(token):
        raise AssertionError(
            f'Probability {token!r} must be written with exactly two decimal places.'
        )

    with open(path, 'r') as f:
        try:
            actual = json.load(
                f,
                parse_float=parse_float,
                parse_int=reject_integer,
                parse_constant=lambda token: (_ for _ in ()).throw(
                    AssertionError(f'Invalid JSON numeric value: {token}')
                ),
            )
        except json.JSONDecodeError as exc:
            raise AssertionError(f'File {path} is not valid JSON: {exc}')

    assert isinstance(actual, dict), 'Top-level JSON value must be an object.'
    expected_keys = set(expected.keys())
    actual_keys = set(actual.keys())
    assert actual_keys == expected_keys, \
        f'Expected items {expected_keys}, but got {actual_keys}.'

    for x in expected_keys:
        expected_list = expected[x]
        actual_list = actual[x]
        assert isinstance(actual_list, list), f'Value for item {x} must be an array.'
        assert len(actual_list) == len(expected_list), \
            f'Item {x} has incorrect number of recommended items.'

        for index, (exp, act) in enumerate(zip(expected_list, actual_list)):
            assert isinstance(act, dict), f'Entry {index} for item {x} must be an object.'
            assert act.get('item') == exp['item'], \
                f"For item {x}, recommendation at index {index} should be {exp['item']}, got {act.get('item')}."
            assert 'prob' in act, f'Recommendation {index} for item {x} lacks prob.'
            assert isinstance(act['prob'], Decimal), \
                f"Probability for {x}->{exp['item']} must be a JSON number with exactly two decimal places."
            assert float(act['prob']) == exp['prob'], \
                f"For item {x}, recommendation {exp['item']} should have prob {exp['prob']}, got {act['prob']}."


def test_final_state_and_pipeline():
    # Preserve the original verifier's existence and fixture assertions.
    assert SCRIPT.is_file(), f'Script missing: {SCRIPT} was not found.'
    assert SCRIPT.stat().st_size > 0, 'build_model.sh is empty.'
    assert JSON_PATH.is_file(), f'Output file missing: {JSON_PATH} was not found.'
    assert CSV_PATH.is_file(), 'Initial raw_logs.csv is missing.'
    load_and_validate(JSON_PATH, expected_from_csv(CSV_PATH))

    original_csv = CSV_PATH.read_bytes()
    original_json = JSON_PATH.read_bytes()

    suffix = os.urandom(6).hex()
    a, b, c, d, ignored = [f'{name}_{suffix}' for name in ('a', 'b', 'c', 'd', 'ignored')]
    users = [f'user_{suffix}_{n}' for n in range(1, 7)]
    dynamic_csv = f'''user_id,item_id,action_type,timestamp
{users[0]},{a},purchase,1
{users[0]},{a},purchase,2
{users[0]},{b},purchase,3
{users[0]},{c},purchase,4
{users[1]},{a},purchase,5
{users[1]},{b},purchase,6
{users[2]},{a},purchase,7
{users[2]},{b},purchase,8
{users[3]},{a},purchase,9
{users[3]},{c},purchase,10
{users[4]},{d},purchase,11
{users[5]},{ignored},view,12
{users[5]},{a},click,13
'''

    try:
        CSV_PATH.write_text(dynamic_csv)
        expected = expected_from_csv(CSV_PATH)
        if JSON_PATH.exists():
            JSON_PATH.unlink()

        result = subprocess.run(
            ['/bin/bash', '-x', str(SCRIPT)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, \
            f'build_model.sh failed with exit code {result.returncode}:\n{result.stderr}'

        # Reject direct use of the forbidden Python/Perl interpreters in the traced pipeline.
        forbidden = re.compile(
            r'^\++\s+(?:(?:command|exec)\s+)?(?:/[^\s]*/)?(?:python(?:[0-9.]*)?|perl(?:[0-9.]*)?)(?:\s|$)',
            re.MULTILINE,
        )
        assert not forbidden.search(result.stderr), \
            'build_model.sh invoked Python or Perl instead of a Bash/POSIX-utility pipeline.'

        assert JSON_PATH.is_file(), 'Executing build_model.sh did not generate item_probs.json.'
        load_and_validate(JSON_PATH, expected)
    finally:
        CSV_PATH.write_bytes(original_csv)
        JSON_PATH.write_bytes(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
