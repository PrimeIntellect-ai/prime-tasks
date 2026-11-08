#!/bin/bash
set -u
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
cp -a /home/user/legacy_math/inputs.txt "$BACKUP_DIR/inputs.txt"
cp -a /home/user/multiplier.conf "$BACKUP_DIR/multiplier.conf"

restore_originals() {
    cp -a "$BACKUP_DIR/inputs.txt" /home/user/legacy_math/inputs.txt
    cp -a "$BACKUP_DIR/multiplier.conf" /home/user/multiplier.conf
    rm -rf "$BACKUP_DIR"
}
trap restore_originals EXIT

run_calc() {
    rm -f /home/user/legacy_math/final_answer.txt /home/user/legacy_math/sum.txt
    timeout 45s runuser -u user -- env -u CONF_DIR bash -c 'cd /home/user/legacy_math && ./calc.sh' >/tmp/calc-output.txt 2>/tmp/calc-error.txt
}

make_case() {
    local count="$1"
    local expected_file="$2"
    python3 - "$count" "$expected_file" <<'PY'
import secrets
import sys

count = int(sys.argv[1])
expected_file = sys.argv[2]
rng = secrets.SystemRandom()
values = [rng.randint(1, 900000) for _ in range(count)]
multiplier = rng.randint(2, 11)

with open('/home/user/legacy_math/inputs.txt', 'wb') as f:
    for value in values:
        f.write((f'{value:,}\r\n').encode('ascii'))
with open('/home/user/multiplier.conf', 'w') as f:
    f.write(f'{multiplier}\n')
with open(expected_file, 'w') as f:
    f.write(str(sum(value * value for value in values) * multiplier))
PY
    chown user:user /home/user/legacy_math/inputs.txt /home/user/multiplier.conf
}

check_generated_answer() {
    local expected_file="$1"
    python3 - "$expected_file" <<'PY'
import os
import re
import sys

answer_path = '/home/user/legacy_math/final_answer.txt'
assert os.path.isfile(answer_path), 'calc.sh did not create final_answer.txt'
with open(answer_path, 'r') as f:
    actual_text = f.read()
assert re.fullmatch(r'[0-9]+\n?', actual_text), f'final_answer.txt must contain only an integer, got {actual_text!r}'
with open(sys.argv[1], 'r') as f:
    expected = int(f.read())
assert int(actual_text) == expected, f'expected {expected}, got {actual_text.strip()}'
PY
}

run_tests() {
    test -f /home/user/legacy_math/calc.sh || return 1
    test -x /home/user/legacy_math/calc.sh || return 1
    head -n 1 /home/user/legacy_math/calc.sh | grep -Eq '^#!.*(bash|/env +bash)( |$)' || return 1
    bash -n /home/user/legacy_math/calc.sh || return 1

    make_case 160 /tmp/expected-answer-1 || return 1
    run_calc || return 1
    check_generated_answer /tmp/expected-answer-1 || return 1

    make_case 420 /tmp/expected-answer-2 || return 1
    run_calc || return 1
    check_generated_answer /tmp/expected-answer-2 || return 1
    run_calc || return 1
    check_generated_answer /tmp/expected-answer-2 || return 1

    cp -a "$BACKUP_DIR/inputs.txt" /home/user/legacy_math/inputs.txt
    cp -a "$BACKUP_DIR/multiplier.conf" /home/user/multiplier.conf
    run_calc || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_final_answer_correct():
    inputs_path = '/home/user/legacy_math/inputs.txt'
    multiplier_path = '/home/user/multiplier.conf'
    final_answer_path = '/home/user/legacy_math/final_answer.txt'

    assert os.path.isfile(inputs_path), f'File {inputs_path} is missing.'
    assert os.path.isfile(multiplier_path), f'File {multiplier_path} is missing.'
    assert os.path.isfile(final_answer_path), f'File {final_answer_path} is missing. Did you save the final calculated sum?'

    with open(inputs_path, 'r') as f:
        lines = f.readlines()

    total_sum = 0
    for line in lines:
        cleaned = line.strip().replace(',', '')
        if cleaned:
            try:
                val = int(cleaned)
                total_sum += val * val
            except ValueError:
                pytest.fail(f"Could not parse '{line.strip()}' as an integer after cleaning.")

    with open(multiplier_path, 'r') as f:
        multiplier_str = f.read().strip()
        try:
            multiplier = int(multiplier_str)
        except ValueError:
            pytest.fail(f"Could not parse multiplier '{multiplier_str}' as an integer.")

    expected_answer = total_sum * multiplier

    with open(final_answer_path, 'r') as f:
        actual_answer_str = f.read().strip()

    assert actual_answer_str.isdigit(), f"Final answer file should contain only an integer, got: '{actual_answer_str}'"
    assert int(actual_answer_str) == expected_answer, f'Expected final answer to be {expected_answer}, but got {actual_answer_str}. The script might still have a race condition or incorrect math.'
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if run_tests 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
