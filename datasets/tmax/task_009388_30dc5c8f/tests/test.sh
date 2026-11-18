#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import string
import subprocess

PROJECT = '/home/user/waf_util'
WAF = os.path.join(PROJECT, 'waf.out')
EXPECTED_LOG = "Status: 200 OK\n\nStatus: 403 Forbidden\n\n"


def run_waf(query, executable=WAF):
    env = os.environ.copy()
    if query is None:
        env.pop('QUERY_STRING', None)
    else:
        env['QUERY_STRING'] = query
    return subprocess.run([executable], env=env, capture_output=True, text=True, timeout=5)


def test_match_s_extracted():
    assert os.path.isfile(os.path.join(PROJECT, 'match.s')), "match.s was not extracted from deps.tar.gz"


def test_makefile_fixed_and_rebuilds_sources():
    makefile_path = os.path.join(PROJECT, 'Makefile')
    assert os.path.isfile(makefile_path), "Makefile is missing"
    with open(makefile_path, 'r') as f:
        lines = f.readlines()

    has_tabs = any(line.startswith('\t') for line in lines)
    assert has_tabs, "Makefile does not contain tab indentation for rules. Spaces were not replaced with tabs."

    subprocess.run(['make', 'clean'], cwd=PROJECT, capture_output=True, text=True)
    for name in ('waf.out', 'waf.o', 'match.o'):
        path = os.path.join(PROJECT, name)
        if os.path.lexists(path):
            os.remove(path)

    proc = subprocess.run(['make', '--no-builtin-rules'], cwd=PROJECT,
                          capture_output=True, text=True, timeout=30)
    assert proc.returncode == 0, f"make failed:\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    assert os.path.isfile(os.path.join(PROJECT, 'waf.o')), "make did not build waf.o from waf.c"
    assert os.path.isfile(os.path.join(PROJECT, 'match.o')), "make did not build match.o from match.s"
    assert os.path.isfile(WAF), "make did not build waf.out"

    with open(WAF, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "waf.out is not a compiled ELF executable"

    nm = subprocess.run(['nm', WAF], capture_output=True, text=True, timeout=5)
    assert nm.returncode == 0, f"could not inspect waf.out symbols: {nm.stderr}"
    assert any(line.split()[-1:] == ['match_traversal'] for line in nm.stdout.splitlines()), \
        "waf.out does not contain the match_traversal assembly function"


def test_waf_out_built_and_executable():
    assert os.path.isfile(WAF), "waf.out was not built"
    assert os.access(WAF, os.X_OK), "waf.out is not executable"


def test_test_sh_exists():
    assert os.path.isfile(os.path.join(PROJECT, 'test.sh')), "test.sh script is missing"


def test_test_script_runs_binary_and_appends_exact_results():
    test_script = os.path.join(PROJECT, 'test.sh')
    log_path = os.path.join(PROJECT, 'test_results.log')
    assert os.path.isfile(test_script), "test.sh script is missing"

    saved_waf = os.path.join('/tmp', 'saved-waf-' + secrets.token_hex(12))
    calls_path = os.path.join('/tmp', 'waf-calls-' + secrets.token_hex(12))
    os.replace(WAF, saved_waf)
    wrapper = f'''#!/usr/bin/env python3
import json, os
with open({calls_path!r}, 'a') as f:
    f.write(json.dumps({{"query": os.environ.get("QUERY_STRING"), "args": __import__("sys").argv[1:]}}) + "\\n")
q = os.environ.get("QUERY_STRING")
if q is None:
    print("Status: 400 Bad Request\\n")
elif "../" in q:
    print("Status: 403 Forbidden\\n")
else:
    print("Status: 200 OK\\n")
'''
    try:
        with open(WAF, 'w') as f:
            f.write(wrapper)
        os.chmod(WAF, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                      stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        if os.path.lexists(log_path):
            os.remove(log_path)

        first = subprocess.run(['bash', test_script], cwd=PROJECT,
                               capture_output=True, text=True, timeout=15)
        assert first.returncode == 0, f"test.sh failed:\nstdout:\n{first.stdout}\nstderr:\n{first.stderr}"
        assert os.path.isfile(log_path), "test_results.log is missing"
        with open(log_path, 'r') as f:
            content = f.read()
        assert content == EXPECTED_LOG, \
            f"test_results.log content is incorrect. Expected exactly:\n{EXPECTED_LOG!r}\nGot:\n{content!r}"

        second = subprocess.run(['bash', test_script], cwd=PROJECT,
                                capture_output=True, text=True, timeout=15)
        assert second.returncode == 0, f"second test.sh run failed:\nstdout:\n{second.stdout}\nstderr:\n{second.stderr}"
        with open(log_path, 'r') as f:
            content = f.read()
        assert content == EXPECTED_LOG * 2, "test.sh does not append both outputs to the existing log"

        assert os.path.isfile(calls_path), "test.sh did not execute waf.out"
        with open(calls_path, 'r') as f:
            calls = [json.loads(line) for line in f if line.strip()]
        expected_calls = [
            {"query": "id=123", "args": []},
            {"query": "file=../../etc/passwd", "args": []},
            {"query": "id=123", "args": []},
            {"query": "file=../../etc/passwd", "args": []},
        ]
        assert calls == expected_calls, \
            f"test.sh must run waf.out twice in the required order on each invocation; got {calls!r}"
    finally:
        if os.path.lexists(WAF):
            os.remove(WAF)
        if os.path.exists(saved_waf):
            os.replace(saved_waf, WAF)
        if os.path.exists(calls_path):
            os.remove(calls_path)


def test_waf_out_behavior():
    fixed = [
        ('id=123', "Status: 200 OK\n\n"),
        ('file=../../etc/passwd', "Status: 403 Forbidden\n\n"),
        (None, "Status: 400 Bad Request\n\n"),
        ('../', "Status: 403 Forbidden\n\n"),
        ('x../y', "Status: 403 Forbidden\n\n"),
        ('file=%2e%2e%2fetc', "Status: 200 OK\n\n"),
        ('file=..\\etc', "Status: 200 OK\n\n"),
    ]
    for query, expected in fixed:
        proc = run_waf(query)
        assert proc.returncode == 0, f"waf.out exited with {proc.returncode} for {query!r}"
        assert proc.stderr == '', f"waf.out wrote unexpected stderr for {query!r}: {proc.stderr!r}"
        assert proc.stdout == expected, f"incorrect output for QUERY_STRING={query!r}: {proc.stdout!r}"

    rng = secrets.SystemRandom()
    safe_chars = string.ascii_letters + string.digits + '_-=/&%'
    for _ in range(24):
        safe = ''.join(rng.choice(safe_chars) for _ in range(rng.randint(4, 80)))
        proc = run_waf(safe)
        assert proc.returncode == 0
        assert proc.stderr == ''
        assert proc.stdout == "Status: 200 OK\n\n", f"random safe query was rejected: {safe!r}"

        prefix = ''.join(rng.choice(safe_chars) for _ in range(rng.randint(0, 40)))
        suffix = ''.join(rng.choice(safe_chars) for _ in range(rng.randint(1, 40)))
        malicious = prefix + '../' + suffix
        proc = run_waf(malicious)
        assert proc.returncode == 0
        assert proc.stderr == ''
        assert proc.stdout == "Status: 403 Forbidden\n\n", \
            f"random traversal query was not rejected: {malicious!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
