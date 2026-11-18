#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_pipeline.py
import json
import os
import random
import secrets
import shutil
import subprocess
import traceback
from pathlib import Path

PIPELINE = Path('/home/user/pipeline.sh')
RAW = Path('/home/user/data/raw_data.csv')
FILTERED = Path('/home/user/data/filtered.csv')
EVALUATOR = Path('/home/user/scripts/evaluate.py')
REPORT = Path('/home/user/best_model.log')

ORIGINAL_RAW = '''id,val1,val2,label
1,0.8,0.2,1
2,0.4,0.1,0
3,0.9,0.3,1
4,0.1,0.9,1
5,0.2,0.5,0
'''

ORIGINAL_EVALUATOR = '''import argparse
import os
import sys

def main():
    if os.environ.get("PIPELINE_MODE") != "STRICT":
        print("")
        sys.exit(0)

    parser = argparse.ArgumentParser()
    parser.add_argument("--param", type=float, required=True)
    parser.add_argument("--input", type=str, required=True)
    args = parser.parse_args()

    # Deterministic mock outputs for testing
    if args.param == 0.1:
        score, ci_l, ci_u = 0.40, 0.30, 0.50
    elif args.param == 0.5:
        score, ci_l, ci_u = 0.70, 0.55, 0.85
    elif args.param == 0.9:
        score, ci_l, ci_u = 0.95, 0.45, 1.45
    else:
        score, ci_l, ci_u = 0.0, 0.0, 0.0

    print(f"SCORE: {score:.2f} CI_LOWER: {ci_l:.2f} CI_UPPER: {ci_u:.2f}")

if __name__ == "__main__":
    main()
'''


def run_pipeline():
    env = os.environ.copy()
    env.pop('PIPELINE_MODE', None)
    for artifact in (FILTERED, REPORT):
        try:
            artifact.unlink()
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [str(PIPELINE)], cwd='/home/user', env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=20
    )
    assert result.returncode == 0, (
        f'pipeline.sh exited with {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )


def assert_original_outputs():
    # Preserve the original verifier's assertions.
    assert FILTERED.is_file(), f'File {FILTERED} is missing. The ETL step was not completed correctly.'
    with FILTERED.open() as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = [
        'id,val1,val2,label',
        '1,0.8,0.2,1',
        '3,0.9,0.3,1',
        '4,0.1,0.9,1',
    ]
    assert lines == expected_lines, (
        f'Content of {FILTERED} does not match the expected filtered data. '
        'It should contain the header and rows where label is exactly 1.'
    )

    assert REPORT.is_file(), f'File {REPORT} is missing. The reporting step was not completed correctly.'
    content = REPORT.read_text().strip()
    expected_content = 'Best Param: 0.5, Score: 0.70, CI: [0.55, 0.85]'
    assert content == expected_content, (
        f'Content of {REPORT} is incorrect. Expected exactly {expected_content!r}, but got {content!r}.'
    )


def dynamic_behavior_test():
    nonce = secrets.token_hex(6)
    dynamic_raw = (
        'id,val1,val2,label\n'
        f'{nonce}a,7.3,8.4,0\n'
        f'{nonce}b,1.1,2.2,1\n'
        f'{nonce}c,3.3,4.4,2\n'
        f'{nonce}d,5.5,6.6,1\n'
        f'{nonce}e,9.1,9.2,0\n'
    )
    expected_filtered = (
        'id,val1,val2,label\n'
        f'{nonce}b,1.1,2.2,1\n'
        f'{nonce}d,5.5,6.6,1\n'
    )

    params = ['0.1', '0.5', '0.9']
    invalid = random.choice(params)
    valid = [p for p in params if p != invalid]
    winner = random.choice(valid)
    other = valid[0] if valid[1] == winner else valid[1]

    outputs = {}
    outputs[invalid] = ('0.99', '0.50', '1.00')
    winner_score = random.randint(78, 93) / 100
    other_score = random.randint(55, 70) / 100
    for p, score in ((winner, winner_score), (other, other_score)):
        lower = random.randint(51, 67) / 100
        upper = min(0.99, lower + random.randint(12, 25) / 100)
        outputs[p] = (f'{score:.2f}', f'{lower:.2f}', f'{upper:.2f}')

    invocation_log = f'/tmp/evaluator_calls_{nonce}.jsonl'
    evaluator_source = f'''#!/usr/bin/env python3
import argparse
import json
import os
import sys

EXPECTED_INPUT = {expected_filtered!r}
OUTPUTS = {outputs!r}
LOG = {invocation_log!r}

parser = argparse.ArgumentParser()
parser.add_argument("--param", required=True)
parser.add_argument("--input", required=True)
args = parser.parse_args()

if os.environ.get("PIPELINE_MODE") != "STRICT":
    print("PIPELINE_MODE was not exported as STRICT", file=sys.stderr)
    sys.exit(41)
if args.input != "/home/user/data/filtered.csv":
    print("wrong --input path", file=sys.stderr)
    sys.exit(42)
try:
    actual = open(args.input).read()
except OSError as exc:
    print(exc, file=sys.stderr)
    sys.exit(43)
if actual != EXPECTED_INPUT:
    print("evaluation was called with incorrectly filtered data", file=sys.stderr)
    sys.exit(44)
try:
    normalized = format(float(args.param), ".1f")
except ValueError:
    sys.exit(45)
if normalized not in OUTPUTS:
    print("unexpected parameter", file=sys.stderr)
    sys.exit(46)
with open(LOG, "a") as f:
    f.write(json.dumps({{"param": normalized, "input": args.input}}) + "\\n")
score, lower, upper = OUTPUTS[normalized]
print(f"SCORE: {{score}} CI_LOWER: {{lower}} CI_UPPER: {{upper}}")
'''

    RAW.write_text(dynamic_raw)
    EVALUATOR.write_text(evaluator_source)
    EVALUATOR.chmod(0o755)
    try:
        Path(invocation_log).unlink()
    except FileNotFoundError:
        pass

    run_pipeline()

    assert FILTERED.read_text() == expected_filtered, (
        'pipeline.sh did not derive filtered.csv from the changed raw_data.csv'
    )
    assert Path(invocation_log).is_file(), 'pipeline.sh never invoked evaluate.py'
    calls = [json.loads(line) for line in Path(invocation_log).read_text().splitlines() if line]
    assert [c['param'] for c in calls] == params, (
        f'evaluate.py must be called once for each parameter in loop order; calls were {calls!r}'
    )
    assert all(c['input'] == '/home/user/data/filtered.csv' for c in calls)

    score, lower, upper = outputs[winner]
    expected_report = f'Best Param: {winner}, Score: {score}, CI: [{lower}, {upper}]'
    assert REPORT.is_file(), 'pipeline.sh did not generate best_model.log'
    assert REPORT.read_text().strip() == expected_report, (
        f'pipeline.sh did not parse the runtime evaluation results and apply CI_LOWER > 0.5; '
        f'expected {expected_report!r}, got {REPORT.read_text().strip()!r}'
    )


def main():
    assert PIPELINE.is_file() and not PIPELINE.is_symlink(), 'pipeline.sh is missing or is not a regular script'
    assert os.access(PIPELINE, os.X_OK), 'pipeline.sh is not executable'
    first_line = PIPELINE.read_text(errors='replace').splitlines()[0] if PIPELINE.stat().st_size else ''
    assert first_line.startswith('#!') and 'bash' in first_line, 'pipeline.sh must remain an executable Bash script'

    # The instruction explicitly forbids modifying these inputs.
    assert RAW.read_text() == ORIGINAL_RAW, 'raw_data.csv was modified'
    assert EVALUATOR.read_text() == ORIGINAL_EVALUATOR, 'evaluate.py was modified'

    raw_backup = RAW.read_bytes()
    evaluator_backup = EVALUATOR.read_bytes()
    evaluator_mode = EVALUATOR.stat().st_mode
    try:
        run_pipeline()
        assert_original_outputs()
        dynamic_behavior_test()
    finally:
        RAW.write_bytes(raw_backup)
        EVALUATOR.write_bytes(evaluator_backup)
        os.chmod(EVALUATOR, evaluator_mode)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        traceback.print_exc()
        raise
PY_EOF

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
