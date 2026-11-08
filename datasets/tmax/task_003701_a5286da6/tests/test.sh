#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import random
import secrets
import shutil
import subprocess
import time
import urllib.parse
import urllib.request

import pytest
import redis

ORACLE = '/app/oracle.py'
SOURCE = '/home/user/fasteval.cpp'
BINARY = '/home/user/fasteval'


def generate_rpn(length, rng):
    if length % 2 == 0:
        length += 1
    operands_left = (length + 1) // 2
    operators_left = (length - 1) // 2
    stack = 0
    expr = []
    while operands_left > 0 or operators_left > 0:
        choices = []
        if operands_left > 0:
            choices.append('num')
        if operators_left > 0 and stack >= 2:
            choices.append('op')
        choice = rng.choice(choices)
        if choice == 'num':
            expr.append(str(rng.randint(-2147483648, 2147483647)))
            stack += 1
            operands_left -= 1
        else:
            expr.append(rng.choice(['+', '-', '*']))
            stack -= 1
            operators_left -= 1
    return ' '.join(expr)


def evaluate(expr):
    stack = []
    for token in expr.split():
        if token in ('+', '-', '*'):
            b = stack.pop()
            a = stack.pop()
            if token == '+':
                stack.append(a + b)
            elif token == '-':
                stack.append(a - b)
            else:
                stack.append(a * b)
        else:
            stack.append(int(token))
    return stack[0]


def run_eval(path, expr):
    result = subprocess.run(
        [path, expr], capture_output=True, text=True, timeout=3
    )
    assert result.returncode == 0, (
        f'{path} failed on {expr!r}: {result.stderr}'
    )
    output = result.stdout.strip()
    assert output == str(evaluate(expr)), (
        f'Output mismatch for {expr!r}: expected {evaluate(expr)}, got {output!r}'
    )


@contextlib.contextmanager
def hidden_oracle():
    assert os.path.isfile(ORACLE), f'Oracle {ORACLE} missing.'
    hidden = f'/tmp/.oracle-hidden-{secrets.token_hex(16)}'
    shutil.move(ORACLE, hidden)
    try:
        yield
    finally:
        if os.path.exists(hidden):
            shutil.move(hidden, ORACLE)


def test_01_fasteval_binary_exists_and_is_native():
    assert os.path.isfile(BINARY), 'The compiled binary /home/user/fasteval does not exist.'
    assert os.access(BINARY, os.X_OK), '/home/user/fasteval is not executable.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/fasteval must be a compiled native executable.'
    assert os.path.isfile(SOURCE), 'The C++ source /home/user/fasteval.cpp does not exist.'


def test_02_original_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f'Oracle {ORACLE} missing.'
    assert os.path.isfile(BINARY), f'Agent binary {BINARY} missing.'
    rng = random.Random(42)
    for _ in range(1000):
        length = rng.choice(range(3, 26, 2))
        expr = generate_rpn(length, rng)
        try:
            oracle_res = subprocess.run(
                ['python3', ORACLE, expr], capture_output=True,
                text=True, check=True, timeout=3
            )
        except subprocess.CalledProcessError:
            continue
        try:
            agent_res = subprocess.run(
                [BINARY, expr], capture_output=True,
                text=True, check=True, timeout=3
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f'Agent binary failed on input {expr!r}: {e.stderr}')
        assert agent_res.stdout.strip() == oracle_res.stdout.strip(), (
            f'Output mismatch on input {expr!r}: expected '
            f'{oracle_res.stdout.strip()!r}, got {agent_res.stdout.strip()!r}'
        )


def test_03_source_compiles_and_binaries_work_without_oracle():
    rebuilt = f'/tmp/fasteval-rebuilt-{secrets.token_hex(8)}'
    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE, '-o', rebuilt],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        f'/home/user/fasteval.cpp does not compile: {compile_result.stderr}'
    )

    rng = random.SystemRandom()
    expressions = [
        '3 4 +',
        '3 4 + 2 *',
        '2147483647 1 +',
        '-2147483648 1 -',
        '2147483647 2147483647 * 2147483647 *',
        '5 9 - 3 * 8 +',
    ]
    expressions.extend(generate_rpn(rng.choice(range(3, 22, 2)), rng) for _ in range(150))

    try:
        with hidden_oracle():
            for expr in expressions:
                run_eval(BINARY, expr)
                run_eval(rebuilt, expr)
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)


def test_04_app_py_configured():
    with open('/home/user/app.py', 'r') as f:
        content = f.read()
    assert '/home/user/fasteval' in content, 'app.py does not call /home/user/fasteval'
    assert '6379' in content, 'app.py does not use Redis port 6379'


def test_05_nginx_configured():
    with open('/home/user/nginx.conf', 'r') as f:
        content = f.read()
    assert 'proxy_pass' in content, 'nginx.conf does not contain a proxy_pass directive'
    assert '5000' in content, 'nginx.conf does not proxy to port 5000'


def wait_for_url(url, expected=None, timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                body = response.read().decode('utf-8').strip()
                if response.getcode() == 200 and (expected is None or body == expected):
                    return body
                last_error = AssertionError(f'status={response.getcode()}, body={body!r}')
        except Exception as e:
            last_error = e
        time.sleep(0.15)
    raise AssertionError(f'URL {url} did not become ready: {last_error}')


def test_06_real_services_use_binary_nginx_and_redis():
    subprocess.run(['pkill', '-f', '^python3 /home/user/app.py$'], capture_output=True)
    subprocess.run(['pkill', '-x', 'nginx'], capture_output=True)
    subprocess.run(['redis-cli', '-p', '6379', 'shutdown', 'nosave'], capture_output=True)
    time.sleep(0.3)

    redis_start = subprocess.run(
        ['redis-server', '--port', '6379', '--daemonize', 'yes',
         '--save', '', '--appendonly', 'no'],
        capture_output=True, text=True, timeout=5
    )
    assert redis_start.returncode == 0, f'Could not start Redis: {redis_start.stderr}'
    cache = redis.Redis(host='127.0.0.1', port=6379)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            if cache.ping():
                break
        except redis.exceptions.ConnectionError:
            time.sleep(0.1)
    else:
        pytest.fail('Redis did not start on port 6379')
    cache.flushdb()

    nginx_test = subprocess.run(
        ['nginx', '-t', '-c', '/home/user/nginx.conf'],
        capture_output=True, text=True, timeout=5
    )
    assert nginx_test.returncode == 0, f'Invalid nginx.conf: {nginx_test.stderr}'

    binary_backup = f'/tmp/.fasteval-hidden-{secrets.token_hex(16)}'
    probe_log = f'/tmp/.fasteval-probe-{secrets.token_hex(16)}'
    oracle_hidden = f'/tmp/.oracle-service-hidden-{secrets.token_hex(16)}'
    app_proc = None
    binary_moved = False
    oracle_moved = False

    try:
        shutil.move(BINARY, binary_backup)
        binary_moved = True
        shutil.move(ORACLE, oracle_hidden)
        oracle_moved = True

        with open(BINARY, 'w') as f:
            f.write('#!/bin/sh\nprintf "%s" "$1" > ' + probe_log + '\nprintf "424242\\n"\n')
        os.chmod(BINARY, 0o755)

        app_proc = subprocess.Popen(
            ['python3', '/home/user/app.py'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        nginx_start = subprocess.run(
            ['nginx', '-c', '/home/user/nginx.conf'],
            capture_output=True, text=True, timeout=5
        )
        assert nginx_start.returncode == 0, f'Nginx failed to start: {nginx_start.stderr}'

        probe_expr = f'{secrets.randbelow(1000000) + 10} 1 +'
        probe_url = 'http://127.0.0.1:8080/api/eval?q=' + urllib.parse.quote(probe_expr)
        assert wait_for_url(probe_url, '424242') == '424242'
        assert os.path.isfile(probe_log), 'Flask did not execute /home/user/fasteval'
        with open(probe_log) as f:
            assert f.read() == probe_expr, 'Flask passed the wrong expression to fasteval'
        assert cache.get(probe_expr) == b'424242', 'Result was not cached in Redis on port 6379'

        os.unlink(probe_log)
        with open(BINARY, 'w') as f:
            f.write('#!/bin/sh\nprintf "31337\\n"\n')
        os.chmod(BINARY, 0o755)
        assert wait_for_url(probe_url, '424242') == '424242', 'Flask did not read the cached Redis result'

        os.unlink(BINARY)
        shutil.move(binary_backup, BINARY)
        binary_moved = False
        cache.flushdb()

        expr = '3 4 + 2 *'
        url = 'http://127.0.0.1:8080/api/eval?q=' + urllib.parse.quote(expr)
        assert wait_for_url(url, '14') == '14'
        assert cache.get(expr) == b'14', 'End-to-end result was not stored in Redis'

        expr2 = '3 4 +'
        url2 = 'http://127.0.0.1:8080/api/eval?q=' + urllib.parse.quote(expr2)
        assert wait_for_url(url2, '7') == '7'
    finally:
        if app_proc is not None:
            app_proc.terminate()
            try:
                app_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                app_proc.kill()
        subprocess.run(['pkill', '-x', 'nginx'], capture_output=True)
        subprocess.run(['redis-cli', '-p', '6379', 'shutdown', 'nosave'], capture_output=True)
        if binary_moved:
            if os.path.exists(BINARY):
                os.unlink(BINARY)
            if os.path.exists(binary_backup):
                shutil.move(binary_backup, BINARY)
        if oracle_moved and os.path.exists(oracle_hidden):
            shutil.move(oracle_hidden, ORACLE)
        if os.path.exists(probe_log):
            os.unlink(probe_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
