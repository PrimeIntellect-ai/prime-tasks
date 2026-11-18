#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/peewee_probe
cat << 'PROBE_EOF' > /tmp/peewee_probe/sitecustomize.py
import builtins
import os
import sys

_real_import = builtins.__import__
_patched = False

def _watch_import(name, globals=None, locals=None, fromlist=(), level=0):
    global _patched
    result = _real_import(name, globals, locals, fromlist, level)
    if not _patched and (name == 'peewee' or name.startswith('peewee.')):
        module = sys.modules.get('peewee')
        module_file = getattr(module, '__file__', '') if module else ''
        try:
            is_vendored = os.path.commonpath([
                os.path.realpath(module_file), '/app/peewee'
            ]) == '/app/peewee'
        except (TypeError, ValueError):
            is_vendored = False
        database_class = getattr(module, 'Database', None) if module else None
        if is_vendored and database_class is not None:
            original_execute_sql = database_class.execute_sql
            def monitored_execute_sql(self, *args, **kwargs):
                marker = os.environ.get('PEEWEE_QUERY_MARKER')
                if marker:
                    with open(marker, 'a', encoding='utf-8') as marker_file:
                        marker_file.write('peewee-query\n')
                return original_execute_sql(self, *args, **kwargs)
            database_class.execute_sql = monitored_execute_sql
            _patched = True
    return result

builtins.__import__ = _watch_import
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess


def test_peewee_fixed():
    peewee_path = '/app/peewee/peewee.py'
    assert os.path.isfile(peewee_path), f"File {peewee_path} is missing."
    with open(peewee_path, 'r', encoding='utf-8') as f:
        content = f.read()
    assert "INNNER" not in content, "The perturbation 'INNNER' was not fixed in peewee.py."


def test_fuzz_equivalence():
    agent_script = '/home/user/get_metrics.py'
    oracle_script = '/tests/get_metrics_oracle.py'

    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} is missing."

    datacenters = ['us-east-1', 'eu-west-1', 'ap-south-1', 'us-west-2', 'unknown-dc', 'drop table servers;']
    random.seed(42)

    for i in range(100):
        dc = random.choice(datacenters)
        min_size = random.randint(0, 5000000000)
        args = [str(dc), str(min_size)]

        oracle_cmd = ['python3', oracle_script] + args
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed unexpectedly on inputs {args}:\n{oracle_res.stderr}"

        marker = f'/tmp/peewee-query-{os.getpid()}-{i}'
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
        env = os.environ.copy()
        existing_pythonpath = env.get('PYTHONPATH', '')
        env['PYTHONPATH'] = '/tmp/peewee_probe' + (os.pathsep + existing_pythonpath if existing_pythonpath else '')
        env['PEEWEE_QUERY_MARKER'] = marker

        agent_cmd = ['python3', agent_script] + args
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, env=env)

        assert agent_res.returncode == 0, f"Agent script failed on inputs {args}:\n{agent_res.stderr}"
        assert os.path.isfile(marker) and os.path.getsize(marker) > 0, (
            'Agent script did not execute a query through the vendored /app/peewee library.'
        )
        assert agent_res.stdout == oracle_res.stdout, (
            f"Output mismatch on inputs {args} (iteration {i}).\n"
            f"Expected (Oracle):\n{oracle_res.stdout}\n"
            f"Got (Agent):\n{agent_res.stdout}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
