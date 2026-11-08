#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import socket
import subprocess
from pathlib import Path

HOME = Path('/home/user')
TRAFFIC = HOME / 'traffic.csv'
ALLOCATIONS = HOME / 'optimal_allocations.csv'
NGINX_CONF = HOME / 'optimized_nginx.conf'
ORACLE = Path('/app/pricing_oracle')
REAL_ORACLE = Path('/app/pricing_oracle.verifier-real')
QUERY_LOG = Path('/tmp/pricing_oracle_queries.csv')


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=60, **kwargs)


def oracle_answer(rate, units):
    proc = run([str(REAL_ORACLE), str(rate), str(units)])
    assert proc.returncode == 0, proc.stdout
    match = re.fullmatch(r'\s*Latency:\s*([0-9.eE+-]+)\s*ms,\s*Cost:\s*\$([0-9.eE+-]+)\s*', proc.stdout)
    assert match, f'Unexpected oracle output: {proc.stdout!r}'
    return float(match.group(1)), float(match.group(2))


def expected_for_rate(rate):
    for units in range(1, 101):
        latency, cost = oracle_answer(rate, units)
        if latency <= 200.0:
            return units, cost
    raise AssertionError(f'No feasible allocation for request rate {rate}')


def get_expected_min_cost(traffic_file):
    # Preserve the original verifier's independently recomputed cost assertion.
    expected_cost = 0.0
    with open(traffic_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rate = float(row['request_rate'])
            min_a2 = rate * 2.5
            A = math.ceil(math.sqrt(min_a2))
            if A < 1:
                A = 1
            elif A > 100:
                A = 100
            expected_cost += A * 2.5 + rate * 0.01
    return expected_cost


def read_traffic():
    with open(TRAFFIC, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['endpoint_path', 'request_rate']
        return [(row['endpoint_path'], float(row['request_rate'])) for row in reader]


def validate_allocations(expected_traffic):
    assert ALLOCATIONS.is_file(), f'File {ALLOCATIONS} does not exist.'
    with open(ALLOCATIONS, newline='') as f:
        reader = csv.DictReader(f)
        assert 'cost' in reader.fieldnames, "The 'cost' column is missing from optimal_allocations.csv."
        assert reader.fieldnames == ['endpoint_path', 'allocation_units', 'cost'], 'Incorrect allocation CSV headers.'
        rows = list(reader)

    assert len(rows) == len(expected_traffic), 'Allocation CSV must contain exactly one row per traffic endpoint.'
    by_endpoint = {}
    for row in rows:
        endpoint = row['endpoint_path']
        assert endpoint not in by_endpoint, f'Duplicate allocation for {endpoint}'
        assert re.fullmatch(r'[0-9]+', row['allocation_units'] or ''), 'allocation_units must be an integer.'
        units = int(row['allocation_units'])
        cost = float(row['cost'])
        assert math.isfinite(cost) and cost > 0
        assert 1 <= units <= 100
        by_endpoint[endpoint] = (units, cost)

    assert set(by_endpoint) == {ep for ep, _ in expected_traffic}, 'Allocation endpoints do not match traffic.csv.'
    total_cost = 0.0
    for endpoint, rate in expected_traffic:
        expected_units, expected_cost = expected_for_rate(rate)
        units, cost = by_endpoint[endpoint]
        assert units == expected_units, f'{endpoint}: expected minimum allocation {expected_units}, got {units}'
        latency, oracle_cost = oracle_answer(rate, units)
        assert latency <= 200.0, f'{endpoint}: allocation is not latency-feasible.'
        if units > 1:
            previous_latency, _ = oracle_answer(rate, units - 1)
            assert previous_latency > 200.0, f'{endpoint}: allocation is not minimal.'
        assert abs(cost - oracle_cost) <= 0.011, f'{endpoint}: reported cost does not match the oracle.'
        assert abs(cost - expected_cost) <= 0.011
        total_cost += cost

    assert total_cost > 0, f'Total cost is {total_cost}, which is invalid.'
    return total_cost


def read_queries():
    queries = []
    if QUERY_LOG.exists():
        for line in QUERY_LOG.read_text().splitlines():
            fields = line.split(',')
            if len(fields) == 2:
                try:
                    queries.append((float(fields[0]), int(fields[1])))
                except ValueError:
                    pass
    return queries


def assert_oracle_was_queried(traffic):
    queries = read_queries()
    for endpoint, rate in traffic:
        units, _ = expected_for_rate(rate)
        matching_units = {u for r, u in queries if math.isclose(r, rate, rel_tol=0, abs_tol=1e-8)}
        assert units in matching_units, f'Optimizer did not query the oracle for {endpoint} at its selected allocation.'
        if units > 1:
            assert units - 1 in matching_units, f'Optimizer did not query the infeasible boundary for {endpoint}.'


def strip_comments(text):
    return '\n'.join(line.split('#', 1)[0] for line in text.splitlines())


def validate_nginx(endpoints):
    assert NGINX_CONF.is_file(), f'Nginx config {NGINX_CONF} does not exist.'
    content = NGINX_CONF.read_text()

    # Preserve all original content assertions.
    assert 'listen 8080' in content or 'listen  8080' in content, 'Nginx config does not listen on port 8080.'
    assert 'proxy_pass http://127.0.0.1:9000' in content, 'Nginx config does not proxy to http://127.0.0.1:9000.'
    assert 'log_format finops' in content or 'log_format  finops' in content, "Nginx config does not define a 'finops' log format."
    assert '/home/user/logs/access.log' in content, 'Nginx config does not log to /home/user/logs/access.log.'
    for endpoint in endpoints:
        assert endpoint in content, f'Nginx config is missing a location block for {endpoint}.'

    clean = strip_comments(content)
    assert re.search(r'\blisten\s+8080(?:\s|;)', clean)
    fmt = re.search(r'\blog_format\s+finops\s+(.+?);', clean, re.S)
    assert fmt, 'Missing syntactically defined finops log format.'
    fmt_text = fmt.group(1)
    assert '$request_time' in fmt_text
    assert '$upstream_response_time' in fmt_text
    assert '$request_uri' in fmt_text or '$uri' in fmt_text
    assert re.search(r'\baccess_log\s+/home/user/logs/access\.log\s+finops\s*;', clean)
    for endpoint in endpoints:
        pattern = r'\blocation\s+(?:=\s*)?' + re.escape(endpoint) + r'\s*\{[^}]*\bproxy_pass\s+http://127\.0\.0\.1:9000\s*;'
        assert re.search(pattern, clean, re.S), f'No valid proxying location block for {endpoint}'

    proc = run(['nginx', '-t', '-c', str(NGINX_CONF)])
    assert proc.returncode == 0, f'Generated Nginx configuration is invalid:\n{proc.stdout}'


def validate_logrotate():
    path = HOME / 'logrotate.conf'
    assert path.is_file(), f'Logrotate config {path} does not exist.'
    content = path.read_text()

    # Preserve original assertions.
    assert 'daily' in content, "logrotate config does not specify 'daily' rotation."
    assert 'rotate 7' in content, "logrotate config does not specify keeping 7 days of logs ('rotate 7')."
    assert 'compress' in content, "logrotate config does not specify 'compress'."

    clean = strip_comments(content)
    assert re.search(r'/home/user/logs/access\.log\s*\{', clean)
    assert re.search(r'(?m)^\s*daily\s*$', clean)
    assert re.search(r'(?m)^\s*rotate\s+7\s*$', clean)
    assert re.search(r'(?m)^\s*compress\s*$', clean)
    os.chmod(HOME, 0o755)
    os.chmod(HOME / 'logs', 0o755)
    proc = run(['logrotate', '-d', str(path)])
    assert proc.returncode == 0, f'Invalid logrotate configuration:\n{proc.stdout}'


def test_complete_pipeline():
    optimizer_cpp = HOME / 'optimizer.cpp'
    deploy = HOME / 'deploy.sh'
    assert optimizer_cpp.is_file(), 'optimizer.cpp is missing.'
    assert deploy.is_file(), 'deploy.sh is missing.'
    assert os.access(deploy, os.X_OK), 'deploy.sh is not executable.'

    source = optimizer_cpp.read_text(errors='replace')
    assert '/app/pricing_oracle' in source, 'Optimizer does not invoke the required oracle path.'
    assert re.search(r'\b(popen|system|fork|exec[a-z]*|posix_spawn)\b', source), 'Optimizer does not spawn the oracle as a subprocess.'

    deploy_text = deploy.read_text(errors='replace')
    assert 'g++' in deploy_text and 'optimizer.cpp' in deploy_text, 'deploy.sh does not compile optimizer.cpp with g++.'
    assert re.search(r'(?:-std=)?(?:gnu\+\+|c\+\+)17', deploy_text), 'deploy.sh does not request C++17.'
    assert re.search(r'optimized_nginx\.conf', deploy_text) and re.search(r'\bnginx\b', deploy_text), 'deploy.sh does not start or reload Nginx with the generated config.'

    original_traffic = TRAFFIC.read_bytes()
    if REAL_ORACLE.exists():
        if ORACLE.exists():
            ORACLE.unlink()
        REAL_ORACLE.rename(ORACLE)
    ORACLE.rename(REAL_ORACLE)
    ORACLE.write_text("#!/bin/sh\nprintf '%s,%s\\n' \"$1\" \"$2\" >> /tmp/pricing_oracle_queries.csv\nexec /app/pricing_oracle.verifier-real \"$@\"\n")
    os.chmod(ORACLE, 0o755)

    try:
        # Compile the submitted source independently and exercise it on derived inputs.
        build = run(['g++', '-std=c++17', str(optimizer_cpp), '-o', '/tmp/submitted_optimizer'])
        assert build.returncode == 0, f'optimizer.cpp does not compile as C++17:\n{build.stdout}'
        probe = [('/verifier/probe-a', 73.0), ('/verifier/probe-b', 431.0), ('/verifier/probe-c', 1999.0)]
        with open(TRAFFIC, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['endpoint_path', 'request_rate'])
            writer.writerows(probe)
        QUERY_LOG.write_text('')
        for path in (ALLOCATIONS, NGINX_CONF):
            if path.exists():
                path.unlink()
        proc = run(['/tmp/submitted_optimizer'], cwd=str(HOME))
        assert proc.returncode == 0, f'Compiled optimizer failed on valid traffic:\n{proc.stdout}'
        validate_allocations(probe)
        assert_oracle_was_queried(probe)
        validate_nginx([ep for ep, _ in probe])

        # Restore the required production input and execute the requested deployment pipeline freshly.
        TRAFFIC.write_bytes(original_traffic)
        production_traffic = read_traffic()
        QUERY_LOG.write_text('')
        for path in (ALLOCATIONS, NGINX_CONF):
            if path.exists():
                path.unlink()
        candidate_binary = HOME / 'optimizer'
        if candidate_binary.exists() and candidate_binary.is_file():
            candidate_binary.unlink()
        proc = run([str(deploy)], cwd=str(HOME))
        assert proc.returncode == 0, f'deploy.sh failed:\n{proc.stdout}'
        assert_oracle_was_queried(production_traffic)

        total_cost = validate_allocations(production_traffic)
        expected_cost = get_expected_min_cost(TRAFFIC)
        threshold_cost = expected_cost + 2.0
        assert total_cost <= threshold_cost, f'Total cost {total_cost} exceeds the threshold of {threshold_cost}. Expected around {expected_cost}.'

        validate_nginx([ep for ep, _ in production_traffic])
        validate_logrotate()

        # Preserve the original process assertion, then require the deployed server to be reachable.
        output = subprocess.check_output(['ps', 'aux']).decode('utf-8')
        assert 'nginx' in output, 'Nginx process is not running.'
        assert 'optimized_nginx.conf' in output, 'Running Nginx was not started with the generated configuration.'
        with socket.create_connection(('127.0.0.1', 8080), timeout=5) as sock:
            sock.sendall(b'GET /api/v1/users HTTP/1.0\r\nHost: localhost\r\n\r\n')
            response = sock.recv(64)
        assert response.startswith(b'HTTP/'), 'Nothing serving HTTP is listening on port 8080.'
    finally:
        TRAFFIC.write_bytes(original_traffic)
        if ORACLE.exists():
            ORACLE.unlink()
        if REAL_ORACLE.exists():
            REAL_ORACLE.rename(ORACLE)
            os.chmod(ORACLE, 0o755)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
