#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_DIR = Path('/home/user/project')
FLOAT = r'(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?'


def expected_count_primes(n):
    count = 0
    for value in range(2, n + 1):
        prime = True
        divisor = 2
        while divisor * divisor <= value:
            if value % divisor == 0:
                prime = False
                break
            divisor += 1
        if prime:
            count += 1
    return count


def parse_report(path):
    content = Path(path).read_text().strip()
    match = re.fullmatch(
        rf'C_avg:\s*({FLOAT})\nPy_avg:\s*({FLOAT})\nSpeedup:\s*({FLOAT})',
        content,
    )
    assert match, 'report.txt must contain exactly the three required lines with finite numeric values.'
    values = tuple(float(value) for value in match.groups())
    assert all(math.isfinite(value) and value > 0 for value in values), 'Report values must be positive and finite.'
    assert math.isclose(values[2], values[1] / values[0], rel_tol=0.05, abs_tol=0.05), \
        'Speedup is not Py_avg / C_avg.'
    return values, content


def fetch(url):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, response.read().decode('utf-8')


def test_directories_created():
    expected_dirs = ['C_src', 'Python_src', 'build', 'config']
    for directory in expected_dirs:
        path = PROJECT_DIR / directory
        assert path.is_dir(), f'Directory {path} was not created.'


def test_files_moved():
    c_file = PROJECT_DIR / 'C_src/prime_c.c'
    py_file = PROJECT_DIR / 'Python_src/prime_py.py'
    assert c_file.is_file(), f'{c_file} is missing. Did you move prime_c.c?'
    assert py_file.is_file(), f'{py_file} is missing. Did you move prime_py.py?'
    assert not (PROJECT_DIR / 'prime_c.c').exists(), 'prime_c.c should not be in the root directory.'
    assert not (PROJECT_DIR / 'prime_py.py').exists(), 'prime_py.py should not be in the root directory.'


def test_shared_library_compiled():
    so_file = PROJECT_DIR / 'build/libprime.so'
    assert so_file.is_file(), f'Shared library {so_file} is missing.'

    library = ctypes.CDLL(str(so_file))
    function = library.count_primes
    function.argtypes = [ctypes.c_int]
    function.restype = ctypes.c_int
    for n in (0, 1, 2, 10, 97, 1000, 50000):
        assert function(n) == expected_count_primes(n), f'C count_primes returned an incorrect result for {n}.'


def test_python_implementation_still_works():
    sys.path.insert(0, str(PROJECT_DIR / 'Python_src'))
    try:
        import prime_py
        for n in (0, 2, 10, 97, 1000):
            assert prime_py.count_primes(n) == expected_count_primes(n)
    finally:
        sys.path.pop(0)
        sys.modules.pop('prime_py', None)


def test_benchmark_script_exists_and_executes_required_calls():
    bench_file = PROJECT_DIR / 'Python_src/benchmark.py'
    assert bench_file.is_file(), f'Benchmark script {bench_file} is missing.'

    so_file = PROJECT_DIR / 'build/libprime.so'
    py_file = PROJECT_DIR / 'Python_src/prime_py.py'
    report_file = PROJECT_DIR / 'build/report.txt'
    original_so = so_file.read_bytes()
    original_py = py_file.read_bytes()
    c_log = Path('/tmp/verifier_c_calls')
    py_log = Path('/tmp/verifier_py_calls')
    c_log.unlink(missing_ok=True)
    py_log.unlink(missing_ok=True)

    probe_source = Path('/tmp/verifier_prime_probe.c')
    probe_so = Path('/tmp/verifier_prime_probe.so')
    probe_source.write_text(r'''#include <stdio.h>
#include <unistd.h>
int count_primes(int n) {
    FILE *f = fopen("/tmp/verifier_c_calls", "a");
    if (f) { fprintf(f, "%d\n", n); fclose(f); }
    usleep(10000);
    return 5133;
}
''')
    subprocess.run(['gcc', '-shared', '-fPIC', str(probe_source), '-o', str(probe_so)], check=True)

    instrumented_values = None
    try:
        so_file.write_bytes(probe_so.read_bytes())
        py_file.write_text("import time\n\ndef count_primes(n):\n    with open('/tmp/verifier_py_calls', 'a') as f:\n        f.write(str(n) + '\\n')\n    time.sleep(0.02)\n    return 5133\n")
        result = subprocess.run(
            [sys.executable, str(bench_file)],
            cwd=str(bench_file.parent),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f'benchmark.py failed when executed: {result.stderr}'
        assert c_log.is_file(), 'benchmark.py did not call count_primes through build/libprime.so.'
        assert py_log.is_file(), 'benchmark.py did not call count_primes imported from prime_py.py.'
        assert c_log.read_text().splitlines() == ['50000'] * 5, \
            'The C count_primes function must be called exactly five times with 50000.'
        assert py_log.read_text().splitlines() == ['50000'] * 5, \
            'The Python count_primes function must be called exactly five times with 50000.'
        instrumented_values, _ = parse_report(report_file)
        assert 0.007 <= instrumented_values[0] <= 0.10, 'C_avg does not reflect the measured C calls.'
        assert 0.015 <= instrumented_values[1] <= 0.20, 'Py_avg does not reflect the measured Python calls.'
    finally:
        so_file.write_bytes(original_so)
        py_file.write_bytes(original_py)

    result = subprocess.run(
        [sys.executable, str(bench_file)],
        cwd=str(bench_file.parent),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f'benchmark.py failed with the submitted implementations: {result.stderr}'
    parse_report(report_file)


def test_report_file_format():
    report_file = PROJECT_DIR / 'build/report.txt'
    assert report_file.is_file(), f'Report file {report_file} is missing.'
    content = report_file.read_text().strip()
    assert re.search(r'C_avg:\s*\d+(\.\d+)?(e-\d+)?', content), 'report.txt is missing a valid C_avg float.'
    assert re.search(r'Py_avg:\s*\d+(\.\d+)?(e-\d+)?', content), 'report.txt is missing a valid Py_avg float.'
    assert re.search(r'Speedup:\s*\d+(\.\d+)?(e-\d+)?', content), 'report.txt is missing a valid Speedup float.'
    parse_report(report_file)


def test_haproxy_config_exists_and_has_required_topology():
    cfg_file = PROJECT_DIR / 'config/haproxy.cfg'
    assert cfg_file.is_file(), f'HAProxy config {cfg_file} is missing.'
    validation = subprocess.run(['haproxy', '-c', '-f', str(cfg_file)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert validation.returncode == 0, f'HAProxy rejected haproxy.cfg: {validation.stdout}{validation.stderr}'

    sections = []
    current = None
    for raw in cfg_file.read_text().splitlines():
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if parts[0].lower() in {'global', 'defaults', 'frontend', 'backend', 'listen'}:
            current = {'kind': parts[0].lower(), 'name': parts[1] if len(parts) > 1 else '', 'lines': []}
            sections.append(current)
        elif current is not None:
            current['lines'].append(parts)

    frontends = [s for s in sections if s['kind'] == 'frontend']
    matching_frontends = [s for s in frontends if any(
        line[0].lower() == 'bind' and line[1].split(',')[0] == '127.0.0.1:8080'
        for line in s['lines'] if len(line) >= 2
    )]
    assert matching_frontends, 'HAProxy must have a frontend bound to 127.0.0.1:8080.'
    backend_names = []
    for frontend in matching_frontends:
        backend_names.extend(line[1] for line in frontend['lines'] if len(line) >= 2 and line[0].lower() == 'default_backend')
    assert backend_names, 'The port 8080 frontend must forward all traffic using default_backend.'
    backends = [s for s in sections if s['kind'] == 'backend' and s['name'] in backend_names]
    assert any(
        line[0].lower() == 'server' and any(token.split(',')[0] == '127.0.0.1:9000' for token in line[2:])
        for backend in backends for line in backend['lines'] if len(line) >= 3
    ), 'The selected backend must contain a server at 127.0.0.1:9000.'


def test_services_running_and_serving_report():
    cfg_path = str(PROJECT_DIR / 'config/haproxy.cfg')
    haproxy_running = False
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            executable = os.path.basename(os.readlink(proc / 'exe'))
            command = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='ignore')
            if executable.startswith('haproxy') and cfg_path in command:
                haproxy_running = True
                break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert haproxy_running, 'HAProxy is not running with the submitted configuration file.'

    expected = (PROJECT_DIR / 'build/report.txt').read_text().strip()
    try:
        direct_status, direct_content = fetch('http://127.0.0.1:9000/report.txt')
        assert direct_status == 200 and direct_content.strip() == expected, \
            'The Python HTTP server on port 9000 is not serving build/report.txt.'
        proxy_status, proxy_content = fetch('http://127.0.0.1:8080/report.txt')
        assert proxy_status == 200, f'Expected HTTP status 200, got {proxy_status}'
        assert proxy_content.strip() == expected, 'HAProxy did not return the actual build/report.txt file.'
        assert 'C_avg:' in proxy_content and 'Py_avg:' in proxy_content and 'Speedup:' in proxy_content, \
            'The file served at http://127.0.0.1:8080/report.txt does not look like the expected report.txt.'
    except urllib.error.URLError as error:
        assert False, f'Failed to connect to HAProxy on port 8080 or the backend server on port 9000: {error}'

    sentinel = PROJECT_DIR / 'verifier_outside_build_token.txt'
    sentinel.write_text('outside-build-token')
    try:
        try:
            _, body = fetch('http://127.0.0.1:9000/verifier_outside_build_token.txt')
            assert 'outside-build-token' not in body, 'The HTTP server exposes files outside the build directory.'
        except urllib.error.HTTPError as error:
            assert error.code in (403, 404), 'Unexpected response while checking the server document root.'
    finally:
        sentinel.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
