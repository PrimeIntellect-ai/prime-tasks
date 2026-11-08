#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import pwd
import re
import stat
import subprocess

import pandas as pd
from sklearn.metrics import mean_squared_error


def run_repair_script():
    script_path = '/home/user/repair_metrics.sh'
    recovered_path = '/home/user/recovered_metrics.csv'

    assert os.path.isfile(script_path), f"File not found: {script_path}"
    assert not os.path.islink(script_path), f"Script must be a regular file, not a symlink: {script_path}"
    assert stat.S_ISREG(os.stat(script_path).st_mode), f"Not a regular file: {script_path}"

    try:
        with open(script_path, 'r', encoding='utf-8') as f:
            script = f.read()
    except Exception as e:
        assert False, f"Failed to read {script_path} as a text script: {e}"

    first_line = script.splitlines()[0] if script.splitlines() else ''
    assert re.fullmatch(r'#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)\s*', first_line), \
        "repair_metrics.sh must be a Bash script"

    forbidden_command = re.compile(
        r'(?im)(?:^|[;&|()]\s*|\b(?:command|exec|env|nohup|sudo)\s+)'
        r'(?:[A-Za-z0-9_./-]*/)?(?:python(?:[0-9.]*)?|pypy(?:[0-9.]*)?|ruby(?:[0-9.]*)?|perl(?:[0-9.]*)?)\b'
    )
    assert not forbidden_command.search(script), \
        "repair_metrics.sh must not invoke Python, Ruby, or Perl"

    try:
        syntax = subprocess.run(
            ['/bin/bash', '-n', script_path], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
    except Exception as e:
        assert False, f"Could not syntax-check repair_metrics.sh: {e}"
    assert syntax.returncode == 0, f"Invalid Bash syntax: {syntax.stderr}"

    # Ensure the submitted artifact, rather than a pre-created final CSV, produces
    # the file being graded. Temporarily disable installed forbidden interpreters
    # while it runs as the unprivileged task user.
    if os.path.lexists(recovered_path):
        os.remove(recovered_path)

    interpreter_modes = {}
    patterns = [
        '/bin/python*', '/usr/bin/python*', '/usr/local/bin/python*',
        '/bin/pypy*', '/usr/bin/pypy*', '/usr/local/bin/pypy*',
        '/bin/ruby*', '/usr/bin/ruby*', '/usr/local/bin/ruby*',
        '/bin/perl*', '/usr/bin/perl*', '/usr/local/bin/perl*',
    ]
    for pattern in patterns:
        for path in glob.glob(pattern):
            real = os.path.realpath(path)
            if real in interpreter_modes or not os.path.isfile(real):
                continue
            mode = stat.S_IMODE(os.stat(real).st_mode)
            interpreter_modes[real] = mode
            os.chmod(real, 0)

    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    try:
        result = subprocess.run(
            ['/bin/bash', script_path],
            cwd='/home/user',
            env={
                'HOME': '/home/user',
                'USER': 'user',
                'LOGNAME': 'user',
                'PATH': '/usr/local/bin:/usr/bin:/bin',
                'LANG': 'C.UTF-8',
            },
            preexec_fn=demote,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
    except Exception as e:
        assert False, f"Failed to execute repair_metrics.sh: {e}"
    finally:
        for path, mode in interpreter_modes.items():
            os.chmod(path, mode)

    assert result.returncode == 0, \
        f"repair_metrics.sh failed with exit code {result.returncode}: {result.stderr}"
    assert os.path.isfile(recovered_path), \
        f"repair_metrics.sh did not create {recovered_path}"


def test_recovered_metrics_mse():
    recovered_path = '/home/user/recovered_metrics.csv'
    reference_path = '/app/reference_metrics.csv'

    run_repair_script()

    assert os.path.isfile(recovered_path), f"File not found: {recovered_path}"
    assert os.path.isfile(reference_path), f"Reference file not found: {reference_path}"

    try:
        df_sub = pd.read_csv(recovered_path)
    except Exception as e:
        assert False, f"Failed to read {recovered_path} as CSV: {e}"

    try:
        df_ref = pd.read_csv(reference_path)
    except Exception as e:
        assert False, f"Failed to read {reference_path} as CSV: {e}"

    assert 'value' in df_sub.columns, f"Missing 'value' column in {recovered_path}"
    assert 'value' in df_ref.columns, f"Missing 'value' column in {reference_path}"
    assert 'timestamp' in df_sub.columns, f"Missing 'timestamp' column in {recovered_path}"
    assert 'timestamp' in df_ref.columns, f"Missing 'timestamp' column in {reference_path}"
    assert list(df_sub.columns) == ['timestamp', 'value'], \
        f"CSV header must be exactly timestamp,value; got {list(df_sub.columns)}"

    # Ensure lengths match
    assert len(df_sub) == len(df_ref), f"Row count mismatch: expected {len(df_ref)}, got {len(df_sub)}"

    # Sort by timestamp to ensure alignment before comparison
    df_sub_sorted = df_sub.sort_values('timestamp').reset_index(drop=True)
    df_ref_sorted = df_ref.sort_values('timestamp').reset_index(drop=True)

    assert df_sub_sorted['timestamp'].tolist() == df_ref_sorted['timestamp'].tolist(), \
        "Recovered timestamps do not exactly match the reference timestamps"

    mse = mean_squared_error(df_ref_sorted['value'], df_sub_sorted['value'])

    assert mse <= 0.0001, f"MSE is too high: {mse} (threshold is <= 0.0001)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
