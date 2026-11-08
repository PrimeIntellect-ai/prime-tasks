#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

DISABLED_PATHS=()
restore_interpreters() {
    local i path backup
    for ((i=${#DISABLED_PATHS[@]}-1; i>=0; i--)); do
        path="${DISABLED_PATHS[$i]}"
        backup="${path}.__verifier_disabled"
        if [ -e "$backup" ] || [ -L "$backup" ]; then
            mv -- "$backup" "$path" 2>/dev/null || true
        fi
    done
}
trap restore_interpreters EXIT

disable_interpreters() {
    local path base backup
    while IFS= read -r -d '' path; do
        base="${path##*/}"
        case "$base" in
            python|python[0-9]*|pypy|pypy[0-9]*|perl|perl[0-9]*|ruby|ruby[0-9]*|node|nodejs|R|Rscript)
                backup="${path}.__verifier_disabled"
                rm -f -- "$backup"
                if mv -- "$path" "$backup"; then
                    DISABLED_PATHS+=("$path")
                else
                    return 1
                fi
                ;;
        esac
    done < <(find /bin /usr/bin /usr/local/bin /opt -maxdepth 2 \( -type f -o -type l \) -print0 2>/dev/null)
    return 0
}

run_optimizer() {
    rm -f /home/user/weights.csv
    runuser -u user -- /usr/bin/timeout 45s /bin/bash /home/user/optimize.sh
}

prepare_cases() {
    python3 - <<'PY'
import csv
import math
import os
import random
import secrets

rng = random.Random(secrets.randbits(256))
models = []
while len(models) < 2:
    candidate = (
        rng.uniform(-7.0, 7.0),
        rng.uniform(-7.0, 7.0),
        rng.uniform(-4.0, 4.0),
    )
    if abs(candidate[0] - 4.5) > 0.8 and abs(candidate[1] + 2.0) > 0.8 and abs(candidate[2] - 1.5) > 0.8:
        models.append(candidate)

with open('/tmp/dynamic_expected.csv', 'w', newline='') as expected:
    ew = csv.writer(expected)
    for case_no, (w1, w2, bias) in enumerate(models, 1):
        path = f'/tmp/training_case_{case_no}.csv'
        with open(path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['x1', 'x2', 'y'])
            for _ in range(1000):
                x1 = rng.uniform(-10.0, 10.0)
                x2 = rng.uniform(-10.0, 10.0)
                noise = rng.gauss(0.0, 0.35)
                y = w1*x1 + w2*x2 + bias + noise
                writer.writerow([round(x1, 4), round(x2, 4), round(y, 4)])
        ew.writerow([case_no, repr(w1), repr(w2), repr(bias)])
PY
    chmod 644 /tmp/training_case_*.csv /tmp/dynamic_expected.csv
}

exercise_submission() {
    [ -f /home/user/training_data.csv ] || return 1
    [ -f /home/user/optimize.sh ] || return 1
    [ ! -L /home/user/optimize.sh ] || return 1
    [ -s /home/user/optimize.sh ] || return 1

    cp /home/user/training_data.csv /tmp/original_training_data.csv || return 1
    prepare_cases || return 1
    disable_interpreters || return 1

    local case_no
    for case_no in 1 2; do
        cp "/tmp/training_case_${case_no}.csv" /home/user/training_data.csv || return 1
        chown user:user /home/user/training_data.csv || return 1
        run_optimizer || return 1
        [ -f /home/user/weights.csv ] || return 1
        cp /home/user/weights.csv "/tmp/weights_case_${case_no}.csv" || return 1
    done

    cp /tmp/original_training_data.csv /home/user/training_data.csv || return 1
    chown user:user /home/user/training_data.csv || return 1
    run_optimizer || return 1

    restore_interpreters
    DISABLED_PATHS=()
    return 0
}

exercise_ok=0
if exercise_submission; then
    exercise_ok=1
else
    restore_interpreters
    DISABLED_PATHS=()
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re


def read_weights(path):
    assert os.path.exists(path), f"The file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a regular file."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert content, f"The file {path} is empty."
    assert '\n' not in content and '\r' not in content, f"{path} must contain exactly one record."
    parts = content.split(',')
    assert len(parts) == 3, f"The file {path} must contain exactly 3 comma-separated values (w1,w2,b)."
    try:
        values = tuple(map(float, parts))
    except ValueError:
        raise AssertionError(f"The values in {path} could not be parsed as floats: {content}")
    assert all(math.isfinite(v) for v in values), f"The values in {path} must be finite."
    return values


def test_submission_was_exercised():
    assert os.environ.get('EXERCISE_OK') == '1', 'optimize.sh did not successfully run on all verification datasets.'


def test_training_data_exists():
    assert os.path.exists('/home/user/training_data.csv'), 'training_data.csv was not generated.'


def test_optimize_script_exists():
    path = '/home/user/optimize.sh'
    assert os.path.exists(path), 'optimize.sh script is missing.'
    assert os.path.isfile(path), 'optimize.sh is not a file.'
    assert not os.path.islink(path), 'optimize.sh must be a regular Bash script, not a symlink.'
    with open(path, 'rb') as f:
        first_line = f.readline(256).decode('utf-8', 'replace').strip()
    assert re.match(r'^#!.*(?:/|\b)(?:bash)(?:\s|$)', first_line), 'optimize.sh must have a Bash shebang.'


def test_weights_csv_exists_and_correct():
    w1, w2, b = read_weights('/home/user/weights.csv')
    assert abs(w1 - 4.5) < 0.1, f'w1 ({w1}) is not within 0.1 of the expected value 4.5'
    assert abs(w2 - (-2.0)) < 0.1, f'w2 ({w2}) is not within 0.1 of the expected value -2.0'
    assert abs(b - 1.5) < 0.1, f'b ({b}) is not within 0.1 of the expected value 1.5'


def test_optimizer_generalizes_to_unseen_data():
    expected = {}
    with open('/tmp/dynamic_expected.csv', newline='') as f:
        for row in csv.reader(f):
            expected[int(row[0])] = tuple(map(float, row[1:]))
    assert set(expected) == {1, 2}
    for case_no in (1, 2):
        actual = read_weights(f'/tmp/weights_case_{case_no}.csv')
        target = expected[case_no]
        labels = ('w1', 'w2', 'b')
        for label, got, want in zip(labels, actual, target):
            assert abs(got - want) < 0.1, f'case {case_no}: {label} ({got}) is not within 0.1 of the fitted target ({want})'
TEST_EOF

if EXERCISE_OK="$exercise_ok" python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

restore_interpreters
trap - EXIT
exit 0
