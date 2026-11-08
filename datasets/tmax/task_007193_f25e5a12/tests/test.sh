#!/bin/bash
mkdir -p /logs/verifier
WORK="$(mktemp -d /tmp/ensemble-verifier.XXXXXX)"
BACKUP="$WORK/model_fit.py.original"
cp -p /home/user/model_fit.py "$BACKUP"

restore_model() {
    cp -p "$BACKUP" /home/user/model_fit.py 2>/dev/null || true
}
trap restore_model EXIT

rm -f /home/user/all_runs.log /home/user/best_model.txt

WORK="$WORK" python3 - <<'PY'
import json
import os
import secrets

work = os.environ['WORK']
nonce = secrets.token_hex(8)
costs = [f"{1 + secrets.randbelow(800000) / 100000:.5f}" for _ in range(25)]
costs[6] = "0.50000"
costs[18] = "0.50000"  # A tie verifies that the first strictly lowest run wins.
paths = [f"{i}-{nonce}-{(i * 7 + 3) % 25}" for i in range(25)]
data = [{'cost': cost, 'path': path} for cost, path in zip(costs, paths)]

with open(os.path.join(work, 'expected.json'), 'w') as f:
    json.dump(data, f)
os.chmod(os.path.join(work, 'expected.json'), 0o600)

state = os.path.join(work, 'state.txt')
with open(state, 'w') as f:
    f.write('0')
os.chmod(work, 0o777)
os.chmod(state, 0o666)

fixture = f'''import fcntl
import json
import os
import sys

DATA = {data!r}
STATE = {state!r}
CALLS = {os.path.join(work, 'calls.jsonl')!r}

with open(STATE, 'r+') as state_file:
    fcntl.flock(state_file, fcntl.LOCK_EX)
    raw = state_file.read().strip()
    index = int(raw or '0')
    state_file.seek(0)
    state_file.truncate()
    state_file.write(str(index + 1))
    state_file.flush()
    valid_command = (os.path.basename(sys.executable).startswith('python3') and
                     os.path.abspath(sys.argv[0]) == '/home/user/model_fit.py')
    record = {{'index': index, 'valid_command': valid_command}}
    with open(CALLS, 'a') as calls_file:
        calls_file.write(json.dumps(record) + '\\n')

if index >= len(DATA):
    print('Unexpected extra invocation', file=sys.stderr)
    sys.exit(9)

item = DATA[index]
print('Initializing molecular graph...')
print('Running gradient descent optimization...')
print('Iteration 0: intermediate cost 99.00000')
print(f"Final Graph Cost: {{item['cost']}}")
print(f"Optimal Network Path: {{item['path']}}")
'''
with open('/home/user/model_fit.py', 'w') as f:
    f.write(fixture)
os.chmod('/home/user/model_fit.py', 0o555)
PY

RUN_STATUS=0
if ! timeout 60s runuser -u user -- /home/user/ensemble_run.sh >"$WORK/run.stdout" 2>"$WORK/run.stderr"; then
    RUN_STATUS=$?
    # The negated command's status is unavailable here, but any nonzero marker is sufficient.
    RUN_STATUS=1
fi
echo "$RUN_STATUS" > "$WORK/run_status"
restore_model
trap - EXIT

cat > "$WORK/test_final_state.py" <<'TEST_EOF'
import json
import os

WORK = os.environ['VERIFIER_WORK']
with open(os.path.join(WORK, 'expected.json')) as f:
    EXPECTED = json.load(f)


def test_ensemble_script_exists_and_executable():
    script_path = '/home/user/ensemble_run.sh'
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_was_executed_and_model_was_invoked_exactly_25_times():
    with open(os.path.join(WORK, 'run_status')) as f:
        assert f.read().strip() == '0', 'ensemble_run.sh did not complete successfully.'

    calls_path = os.path.join(WORK, 'calls.jsonl')
    assert os.path.exists(calls_path), 'model_fit.py was never invoked.'
    with open(calls_path) as f:
        calls = [json.loads(line) for line in f if line.strip()]

    assert len(calls) == 25, f'Expected exactly 25 model_fit.py invocations, found {len(calls)}.'
    assert [call['index'] for call in calls] == list(range(25)), 'Invocation sequence is invalid.'
    assert all(call['valid_command'] for call in calls), \
        'Every invocation must use python3 /home/user/model_fit.py.'


def test_all_runs_log():
    log_path = '/home/user/all_runs.log'
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 25, f"Expected exactly 25 lines in {log_path}, found {len(lines)}."

    for line in lines:
        assert line.startswith("Cost: "), f"Line in {log_path} does not start with 'Cost: '. Line: {line}"
        assert ", Path: " in line, f"Line in {log_path} does not contain ', Path: '. Line: {line}"

    expected_lines = [f"Cost: {item['cost']}, Path: {item['path']}" for item in EXPECTED]
    assert lines == expected_lines, \
        'all_runs.log does not contain the values emitted by the 25 model runs in run order.'


def test_best_model_output():
    log_path = '/home/user/all_runs.log'
    best_path_file = '/home/user/best_model.txt'

    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    assert os.path.exists(best_path_file), f"Best model file {best_path_file} does not exist."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    min_cost = float('inf')
    best_path = ""
    best_cost_str = ""

    for line in lines:
        parts = line.split(', Path: ')
        assert len(parts) == 2, f"Malformed line in {log_path}: {line}"

        cost_str = parts[0].replace('Cost: ', '').strip()
        path_str = parts[1].strip()

        try:
            cost_val = float(cost_str)
        except ValueError:
            assert False, f"Could not parse cost as float: {cost_str}"

        if cost_val < min_cost:
            min_cost = cost_val
            best_path = path_str
            best_cost_str = cost_str

    with open(best_path_file, 'r') as f:
        best_lines = [line.strip() for line in f if line.strip()]

    assert len(best_lines) == 2, f"Expected exactly 2 lines in {best_path_file}, found {len(best_lines)}."
    assert best_lines[0] == f"Lowest Cost: {best_cost_str}", f"Expected 'Lowest Cost: {best_cost_str}', got '{best_lines[0]}'"
    assert best_lines[1] == f"Best Path: {best_path}", f"Expected 'Best Path: {best_path}', got '{best_lines[1]}'"
TEST_EOF

if VERIFIER_WORK="$WORK" python3 -m pytest "$WORK/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
rm -rf "$WORK"
