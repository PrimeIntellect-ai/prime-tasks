#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import secrets
import shutil
import stat
import string
import subprocess
import tempfile
import pytest


def generate_random_input(seed):
    rng = random.Random(seed)
    num_rows = rng.randint(0, 50)
    lines = []

    for _ in range(num_rows):
        if rng.random() < 0.5:
            session_id = ''.join(rng.choices(string.ascii_letters + string.digits, k=8))
        else:
            session_id = ''.join(
                rng.choices(string.printable, k=rng.randint(1, 15))
            ).replace('\t', '').replace('\n', '')

        if rng.random() < 0.5:
            num_newlines = rng.randint(1, 5)
            inner_text = ''.join(
                rng.choices(string.ascii_letters + string.digits + ' ', k=rng.randint(5, 50))
            )
            chars = list(inner_text)
            for _ in range(num_newlines):
                chars.insert(rng.randint(0, len(chars)), '\n')
            metadata = f"<<{''.join(chars)}>>"
        else:
            metadata = ''.join(
                rng.choices(string.ascii_letters + string.digits, k=rng.randint(1, 20))
            )

        metrics_list = []
        for _ in range(rng.randint(0, 10)):
            if rng.random() < 0.1:
                metrics_list.append('malformed_metric')
                continue
            key = ''.join(
                rng.choices(string.ascii_letters + 'ＣＡＦＥ温度!_ ', k=rng.randint(1, 10))
            )
            metrics_list.append(f'{key}:{rng.randint(-1000, 1000)}')

        metrics = ','.join(metrics_list)
        if rng.random() < 0.1:
            if rng.random() < 0.5:
                row = f'{session_id}\t{metadata}'
            else:
                row = f'{session_id}\t{metadata}\t{metrics}\textra'
        else:
            row = f'{session_id}\t{metadata}\t{metrics}'
        lines.append(row)

    return '\n'.join(lines).encode('utf-8')


def run_unprivileged(argv, input_data, cwd, env):
    account = pwd.getpwnam('nobody')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        argv,
        input=input_data,
        capture_output=True,
        cwd=cwd,
        env=env,
        timeout=5,
        preexec_fn=demote,
    )


def test_fuzz_equivalence():
    oracle_path = '/app/log_analyzer'
    agent_path = '/home/user/solution'

    assert os.path.exists(agent_path), f'Agent solution missing at {agent_path}'
    assert os.path.isfile(agent_path), f'{agent_path} is not a file'
    assert os.access(agent_path, os.X_OK), f'{agent_path} is not executable'
    assert not os.path.islink(agent_path), f'{agent_path} must be a script file, not a symlink'
    assert os.path.getsize(agent_path) <= 1024 * 1024, 'Replacement script is unexpectedly large'

    with open(agent_path, 'rb') as f:
        agent_bytes = f.read()
    assert agent_bytes.startswith(b'#!'), 'Replacement must have a proper shebang'
    assert b'\x00' not in agent_bytes[:4096], 'Replacement must be a script, not a binary executable'

    with open(oracle_path, 'rb') as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, 'Replacement must not be byte-identical to the reference binary'

    # Seeds are chosen only after the agent has finished, so fixed-case hardcoding
    # cannot cover the verifier corpus.
    cases = [generate_random_input(secrets.randbits(128)) for _ in range(200)]
    expected = []
    for input_data in cases:
        proc_oracle = subprocess.run([oracle_path], input=input_data, capture_output=True)
        expected.append(proc_oracle.stdout)

    stage = tempfile.mkdtemp(prefix='log-verifier-', dir='/run')
    hidden = tempfile.mkdtemp(prefix='.oracle-', dir='/run')
    staged_agent = os.path.join(stage, 'solution')
    workdir = os.path.join(stage, 'work')
    hidden_oracle = os.path.join(hidden, 'log_analyzer')
    shutil.copy2(agent_path, staged_agent)
    os.chmod(staged_agent, 0o755)
    os.mkdir(workdir, 0o777)
    os.chmod(stage, 0o755)
    os.chmod(hidden, 0o700)

    # Hide both the reference and locations in which the agent user could have
    # stashed a copy. The submitted standalone script is run as an unprivileged
    # user from a clean staging directory.
    locked = []
    os.replace(oracle_path, hidden_oracle)
    try:
        for path in ('/home/user', '/tmp', '/var/tmp', '/dev/shm'):
            if os.path.isdir(path):
                mode = stat.S_IMODE(os.stat(path).st_mode)
                locked.append((path, mode))
                os.chmod(path, 0o700)

        env = os.environ.copy()
        env['HOME'] = workdir
        env['TMPDIR'] = workdir

        for index, (input_data, oracle_out) in enumerate(zip(cases, expected)):
            proc_agent = run_unprivileged([staged_agent], input_data, workdir, env)
            if proc_agent.stdout != oracle_out:
                pytest.fail(
                    f'Output mismatch on randomized case {index}.\n'
                    f'Input data:\n{input_data.decode("utf-8", errors="replace")}\n'
                    f'Oracle output:\n{oracle_out.decode("utf-8", errors="replace")}\n'
                    f'Agent output:\n{proc_agent.stdout.decode("utf-8", errors="replace")}'
                )
    finally:
        for path, mode in reversed(locked):
            os.chmod(path, mode)
        if os.path.exists(hidden_oracle):
            os.replace(hidden_oracle, oracle_path)
        shutil.rmtree(stage, ignore_errors=True)
        shutil.rmtree(hidden, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
