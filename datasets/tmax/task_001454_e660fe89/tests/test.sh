#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import signal
import string
import subprocess
import tempfile
import time


def descendants(root_pid):
    children = {}
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/stat', 'r') as f:
                stat = f.read()
            ppid = int(stat.rsplit(')', 1)[1].split()[1])
            children.setdefault(ppid, []).append(int(entry))
        except (OSError, ValueError, IndexError):
            pass

    found = []
    pending = [root_pid]
    while pending:
        parent = pending.pop()
        for child in children.get(parent, []):
            found.append(child)
            pending.append(child)
    return found


def run_agent(agent_script, csv_path, timeout, require_parallel=False):
    user = pwd.getpwnam('user')

    def demote():
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env['HOME'] = user.pw_dir
    proc = subprocess.Popen(
        [agent_script, csv_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        preexec_fn=demote,
        start_new_session=True,
    )

    saw_parallel = False
    deadline = time.monotonic() + timeout
    try:
        while proc.poll() is None:
            if len(descendants(proc.pid)) >= 2:
                saw_parallel = True
            if time.monotonic() >= deadline:
                os.killpg(proc.pid, signal.SIGKILL)
                raise AssertionError(f'Agent script timed out after {timeout} seconds')
            time.sleep(0.001)
        stdout, stderr = proc.communicate()
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()

    assert proc.returncode == 0, f'Agent script failed with error: {stderr}'
    if require_parallel:
        assert saw_parallel, 'Agent script did not process rows using concurrent worker processes.'
    return stdout, stderr


def oracle_results(oracle_bin, rows):
    outputs = []
    for str1, str2 in rows:
        res = subprocess.run([oracle_bin, str1, str2], capture_output=True, text=True)
        assert res.returncode == 0, f"Oracle failed on inputs: '{str1}', '{str2}'"
        outputs.append(res.stdout.strip())
    return outputs


def test_batch_scorer_fuzz_equivalence_and_constraints():
    agent_script = '/home/user/batch_scorer.sh'
    oracle_bin = '/app/sim_scorer'

    assert os.path.exists(agent_script), f'Agent script {agent_script} not found.'
    assert os.path.isfile(agent_script), f'Agent script {agent_script} is not a regular file.'
    assert os.access(agent_script, os.X_OK), f'Agent script {agent_script} is not executable.'
    assert os.path.exists(oracle_bin), f'Oracle binary {oracle_bin} not found.'

    random.seed(42)
    charset = string.ascii_letters + ' '
    batches = []

    # Preserve the original five fuzz-equivalence batches.
    for _ in range(5):
        num_rows = random.randint(20, 50)
        rows = []
        for _ in range(num_rows):
            len1 = random.randint(1, 100)
            len2 = random.randint(1, 100)
            rows.append((
                ''.join(random.choices(charset, k=len1)),
                ''.join(random.choices(charset, k=len2)),
            ))
        batches.append((rows, oracle_results(oracle_bin, rows), False))

    # A larger batch makes concurrent row workers observable.
    parallel_rows = []
    for _ in range(240):
        parallel_rows.append((
            ''.join(random.choices(charset, k=300)),
            ''.join(random.choices(charset, k=300)),
        ))
    batches.append((parallel_rows, oracle_results(oracle_bin, parallel_rows), True))

    # Make the legacy executable unavailable while the submitted implementation
    # runs. A replacement records any attempted invocation of the forbidden path.
    backup = tempfile.mktemp(prefix='.sim_scorer.', dir='/root')
    marker = tempfile.mktemp(prefix='sim_scorer_invoked.', dir='/tmp')
    os.rename(oracle_bin, backup)
    with open(oracle_bin, 'w') as f:
        f.write('#!/bin/sh\nprintf invoked > ' + marker + '\nexit 97\n')
    os.chmod(oracle_bin, 0o755)

    try:
        for batch_idx, (rows, expected_outputs, require_parallel) in enumerate(batches):
            if os.path.exists(marker):
                os.remove(marker)

            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.csv') as tmp:
                for str1, str2 in rows:
                    tmp.write(f'{str1},{str2}\n')
                tmp_path = tmp.name
            os.chmod(tmp_path, 0o644)

            try:
                stdout, _ = run_agent(
                    agent_script,
                    tmp_path,
                    timeout=20 if require_parallel else 15,
                    require_parallel=require_parallel,
                )
                assert not os.path.exists(marker), \
                    'Agent script invoked the forbidden /app/sim_scorer binary.'

                agent_outputs = stdout.strip().split('\n')
                agent_outputs = [out for out in agent_outputs if out.strip()]
                assert len(agent_outputs) == len(rows), \
                    f'Expected {len(rows)} outputs from agent script, but got {len(agent_outputs)}.'

                for row_idx, (expected, actual) in enumerate(zip(expected_outputs, agent_outputs)):
                    csv_line = f'{rows[row_idx][0]},{rows[row_idx][1]}'
                    assert expected == actual.strip(), \
                        f'Mismatch at row {row_idx + 1} in batch {batch_idx + 1}.\n' \
                        f'Input row: {csv_line}\n' \
                        f'Oracle output: {expected}\n' \
                        f'Agent output: {actual.strip()}'
            finally:
                os.remove(tmp_path)
    finally:
        try:
            os.remove(oracle_bin)
        except FileNotFoundError:
            pass
        os.rename(backup, oracle_bin)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
