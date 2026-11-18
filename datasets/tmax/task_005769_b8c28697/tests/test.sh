#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pathlib
import random
import re
import secrets
import shutil
import subprocess

PROJECT = pathlib.Path('/home/user/tester')
RESULT = PROJECT / 'result.txt'
BUILD = pathlib.Path('/tmp/verifier-build')


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=60, **kwargs)


def pair_count(values, threshold):
    return sum(1 for i in range(len(values)) for j in range(i + 1, len(values))
               if values[i] + values[j] == threshold)


def read_result(expected):
    assert RESULT.is_file(), f'Expected output file {RESULT} does not exist.'
    raw = RESULT.read_text()
    assert re.fullmatch(r'-?\d+\n?', raw), f'result.txt must contain one integer alone, found {raw!r}'
    actual = int(raw.strip())
    assert actual == expected, f'Expected result.txt to contain {expected}, but found {actual}.'


def execute(analyzer, url, factor, library_dir):
    RESULT.unlink(missing_ok=True)
    env = os.environ.copy()
    old_path = env.get('LD_LIBRARY_PATH', '')
    env['LD_LIBRARY_PATH'] = str(library_dir) + (':' + old_path if old_path else '')
    proc = subprocess.run([str(analyzer), url], cwd=PROJECT, env=env,
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=15)
    assert proc.returncode == 0, f'analyzer failed for {url!r}: {proc.stderr}'
    data_text = url.split('data=', 1)[1].split('&threshold=', 1)[0]
    threshold = int(url.rsplit('&threshold=', 1)[1])
    values = [int(item) for item in data_text.split(',')]
    read_result(pair_count(values, threshold) * factor)


def main():
    # Preserve the original final-state assertions: the requested execution must
    # already have produced result.txt containing 168.
    assert RESULT.is_file(), f'Expected output file {RESULT} does not exist. Did you run the executable?'
    with RESULT.open() as f:
        content = f.read().strip()
    assert content == '168', f"Expected result.txt to contain '168', but found '{content}'."

    assert (PROJECT / 'CMakeLists.txt').is_file()
    assert (PROJECT / 'src/analyzer.cpp').is_file()
    assert (PROJECT / 'lib/libmetric.so').is_file()

    # Build from a clean directory so a stale or hand-written result cannot pass.
    shutil.rmtree(BUILD, ignore_errors=True)
    run(['cmake', '-S', str(PROJECT), '-B', str(BUILD)])
    run(['cmake', '--build', str(BUILD), '--clean-first', '--parallel', '2'])
    analyzer = BUILD / 'analyzer'
    assert analyzer.is_file() and os.access(analyzer, os.X_OK), 'CMake did not build executable target analyzer'
    assert analyzer.read_bytes()[:4] == b'\x7fELF', 'analyzer is not a compiled ELF executable'

    # Confirm the produced program is dynamically linked to the supplied API and
    # leaves initialize_metrics to be resolved from that library.
    dynamic = run(['readelf', '-d', str(analyzer)]).stdout
    assert re.search(r'Shared library: \[libmetric\.so\]', dynamic), 'analyzer does not depend on libmetric.so'
    symbols = run(['nm', '-D', '-C', str(analyzer)]).stdout
    assert re.search(r'\bU\s+initialize_metrics\(\)', symbols), 'analyzer does not import initialize_metrics()'

    metric = ctypes.CDLL(str(PROJECT / 'lib/libmetric.so'))
    metric.initialize_metrics.restype = ctypes.c_int
    real_factor = metric.initialize_metrics()
    assert real_factor == 42, 'The supplied metric library was modified or is invalid'

    # Re-run the required URL using the freshly built executable.
    execute(analyzer, 'api://test/run?data=12,18,5,25,15,15,30,0&threshold=30',
            real_factor, PROJECT / 'lib')

    # Exercise URL parsing and index-pair counting on unpredictable inputs.
    rng = random.SystemRandom()
    for n in (7, 12, 19):
        threshold = rng.randint(-45, 45)
        left = rng.randint(-50, 50)
        values = [rng.randint(-50, 50) for _ in range(n - 2)] + [left, threshold - left]
        rng.shuffle(values)
        url = f'metric://host{secrets.token_hex(3)}/v1/run?data=' + ','.join(map(str, values)) + f'&threshold={threshold}'
        execute(analyzer, url, real_factor, PROJECT / 'lib')

    # Substitute another ABI-compatible libmetric.so. A correct implementation
    # must use the value returned by initialize_metrics rather than hardcoding 42.
    probe_dir = pathlib.Path('/tmp/verifier-metric')
    shutil.rmtree(probe_dir, ignore_errors=True)
    probe_dir.mkdir()
    probe_factor = rng.choice([x for x in range(3, 98) if x != 42])
    source = probe_dir / 'metric.cpp'
    source.write_text(f'int initialize_metrics() {{ return {probe_factor}; }}\n')
    run(['g++', '-shared', '-fPIC', str(source), '-o', str(probe_dir / 'libmetric.so')])

    threshold = rng.randint(-30, 30)
    values = [threshold, 0, 4, threshold - 4, -7, threshold + 7, 11, 11, 11]
    rng.shuffle(values)
    url = 'probe://runtime/check?data=' + ','.join(map(str, values)) + f'&threshold={threshold}'
    execute(analyzer, url, probe_factor, probe_dir)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
