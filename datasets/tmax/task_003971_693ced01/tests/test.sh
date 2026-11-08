#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
import time


def run_filter(payload, extra_args=None):
    cmd = ['bash']
    if extra_args:
        cmd.extend(extra_args)
    cmd.append('/home/user/gateway_filter.sh')
    return subprocess.run(cmd, input=payload, capture_output=True, text=True, timeout=10)


def assert_classification(payload, accept, label):
    result = run_filter(payload)
    expected_code = 0 if accept else 1
    expected_output = 'ACCEPT' if accept else 'REJECT'
    assert result.returncode == expected_code, (
        f'{label}: expected exit {expected_code}, got {result.returncode}; '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert result.stdout.strip() == expected_output, (
        f'{label}: expected {expected_output!r}, got {result.stdout!r}'
    )


def test_go_httpbin_compiled():
    binary_path = '/app/go-httpbin/httpbin'
    assert os.path.isfile(binary_path), f'The binary {binary_path} was not compiled.'
    assert os.access(binary_path, os.X_OK), f'The binary {binary_path} is not executable.'

    result = subprocess.run([binary_path, '-h'], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Running '{binary_path} -h' failed with exit code {result.returncode}."
    assert re.search(r'usage|help', result.stdout + result.stderr, re.I), 'The compiled binary did not display help text.'

    with open(binary_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'httpbin must be a compiled Linux binary, not an arbitrary script.'

    metadata = subprocess.run(['go', 'version', '-m', binary_path], capture_output=True, text=True, timeout=15)
    assert metadata.returncode == 0, 'httpbin does not contain valid Go build metadata.'
    assert 'github.com/example/go-httpbin' in metadata.stdout, 'httpbin was not built from the vendored Go module.'

    source = '/app/go-httpbin/cmd/httpbin/main.go'
    assert os.path.isfile(source), f'Missing Go entry point {source}.'
    with open(source, encoding='utf-8') as f:
        source_text = f.read()
    assert 'Fatalff' not in source_text, 'The deliberate Go source perturbation was not fixed.'

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'httpbin')
        build = subprocess.run(
            ['go', 'build', '-o', rebuilt, './cmd/httpbin'],
            cwd='/app/go-httpbin', capture_output=True, text=True, timeout=120
        )
        assert build.returncode == 0, f'The repaired vendored source does not build: {build.stderr}'
        rebuilt_help = subprocess.run([rebuilt, '-h'], capture_output=True, text=True, timeout=10)
        assert rebuilt_help.returncode == 0, 'A fresh build of the repaired source fails its help command.'
        assert rebuilt_help.stdout == result.stdout and rebuilt_help.stderr == result.stderr, (
            'The submitted httpbin behavior does not match a fresh build of the repaired source.'
        )


def test_gateway_filter_exists_and_executable():
    script_path = '/home/user/gateway_filter.sh'
    assert os.path.isfile(script_path), f'The script {script_path} is missing.'
    assert os.access(script_path, os.X_OK), f'The script {script_path} is not executable.'
    syntax = subprocess.run(['bash', '-n', script_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f'gateway_filter.sh has invalid Bash syntax: {syntax.stderr}'

    with open(script_path, encoding='utf-8') as f:
        text = f.read()
    declarations = re.findall(r'\b(?:declare|typeset)\s+(?:-[A-Za-z]*A[A-Za-z]*\s+)([A-Za-z_][A-Za-z0-9_]*)', text)
    assert declarations, 'gateway_filter.sh must declare and use a Bash associative array.'
    assert any(len(re.findall(r'\b' + re.escape(name) + r'\b', text)) >= 3 for name in declarations), (
        'The declared associative array is not used to populate and evaluate the filter data.'
    )
    assert re.search(r'(^|[^A-Za-z0-9_])jq([^A-Za-z0-9_]|$)', text), 'gateway_filter.sh must use jq to parse JSON.'

    probe = json.dumps({'user': {'role': 'admin', 'permissions': ['all', 'read']}})
    traced = run_filter(probe, ['-x'])
    assert traced.returncode == 0 and traced.stdout.strip() == 'ACCEPT', 'The filter failed its traced execution probe.'
    assert re.search(r'^\+.*(?:declare|typeset)\s+.*-A', traced.stderr, re.M), (
        'No associative array declaration was executed while processing a payload.'
    )
    assert re.search(r'^\+.*\bjq\b', traced.stderr, re.M), 'jq was not executed while parsing the payload.'


def test_gateway_filter_against_corpora():
    script_path = '/home/user/gateway_filter.sh'
    clean_dir = '/app/corpora/clean/'
    evil_dir = '/app/corpora/evil/'

    clean_files = glob.glob(os.path.join(clean_dir, '*'))
    evil_files = glob.glob(os.path.join(evil_dir, '*'))

    assert len(clean_files) > 0, f'No clean corpus files found in {clean_dir}.'
    assert len(evil_files) > 0, f'No evil corpus files found in {evil_dir}.'

    clean_failed = []
    for f in clean_files:
        if not os.path.isfile(f):
            continue
        with open(f, 'r') as fd:
            payload = fd.read()
        result = subprocess.run(['bash', script_path], input=payload, capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() != 'ACCEPT':
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        if not os.path.isfile(f):
            continue
        with open(f, 'r') as fd:
            payload = fd.read()
        result = subprocess.run(['bash', script_path], input=payload, capture_output=True, text=True)
        if result.returncode != 1 or result.stdout.strip() != 'REJECT':
            evil_failed.append(os.path.basename(f))

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified or rejected: {', '.join(clean_failed)}")
    if error_msgs:
        raise AssertionError(' | '.join(error_msgs))


def test_gateway_filter_generated_cases():
    token = secrets.token_hex(12)
    accepted = [
        {'user': {'role': 'admin', 'permissions': ['all']}},
        {'user': {'permissions': ['read', 'all', 'write'], 'role': 'admin'}, 'nonce': token},
        {'user': {'role': 'admin', 'permissions': ['all', 'SCRIPT', '<Script>', '', token], 'bitmask': -999}},
        {'user': {'role': 'admin', 'permissions': ['all', 'x<scripture>', 'read']}, 'unexpected': {'x': True}},
    ]

    rejected = [
        {},
        {'user': {}},
        {'user': {'role': 'user', 'permissions': ['all']}},
        {'user': {'role': 'admin', 'permissions': []}},
        {'user': {'role': 'admin', 'permissions': ['read', 'write']}},
        {'user': {'role': 'admin', 'permissions': ['ALL']}},
        {'user': {'role': 'admin', 'permissions': ['all', '<script>']}},
        {'user': {'role': 'admin', 'permissions': ['all', 'prefix<script>suffix']}},
        {'user': {'role': 'admin', 'permissions': ['all', '<script src=x>']}},
        {'user': {'role': 'admin', 'permissions': None}},
        {'user': {'role': 'admin', 'permissions': 'all'}},
        {'user': {'role': ['admin'], 'permissions': ['all']}},
        {'user': token},
        [],
        None,
    ]

    rng = random.SystemRandom()
    for i in range(25):
        marker = secrets.token_hex(8)
        permissions = [marker, 'read', 'all', 'write']
        rng.shuffle(permissions)
        accepted.append({'request': i, 'user': {'permissions': permissions, 'role': 'admin'}})

        bad_kind = i % 4
        if bad_kind == 0:
            bad = {'user': {'role': 'admin', 'permissions': ['read', marker]}}
        elif bad_kind == 1:
            bad = {'user': {'role': 'viewer-' + marker, 'permissions': ['all']}}
        elif bad_kind == 2:
            bad = {'user': {'role': 'admin', 'permissions': ['all', marker + '<script>' + marker]}}
        else:
            bad = {'user': {'role': 'admin', 'permissions': [marker, 7, 'all']}}
        rejected.append(bad)

    for i, obj in enumerate(accepted):
        payload = json.dumps(obj, ensure_ascii=False, separators=(',', ':'))
        assert_classification(payload, True, f'generated accepted case {i}')
    for i, obj in enumerate(rejected):
        payload = json.dumps(obj, ensure_ascii=False, indent=(2 if i % 2 else None))
        assert_classification(payload, False, f'generated rejected case {i}')

    malformed = ['', '{', 'null trailing', '{"user":', '[1,2,', token]
    for i, payload in enumerate(malformed):
        assert_classification(payload, False, f'malformed JSON case {i}')


def parse_elapsed_seconds(content):
    matches = re.findall(r'\breal\s+(\d+)m([0-9]+(?:\.[0-9]+)?)s', content, re.I)
    if matches:
        minutes, seconds = matches[-1]
        return int(minutes) * 60 + float(seconds)
    matches = re.findall(r'([0-9]+(?:\.[0-9]+)?)\s*(milliseconds?|msecs?|ms)\b', content, re.I)
    if matches:
        return float(matches[-1][0]) / 1000.0
    matches = re.findall(r'([0-9]+(?:\.[0-9]+)?)\s*(seconds?|secs?|s)\b', content, re.I)
    if matches:
        return float(matches[-1][0])
    if re.fullmatch(r'\s*[0-9]+(?:\.[0-9]+)?\s*', content):
        return float(content.strip())
    return None


def test_benchmark_artifacts():
    bench_script = '/home/user/benchmark.sh'
    bench_results = '/home/user/benchmark_results.txt'
    filter_path = '/home/user/gateway_filter.sh'
    clean_payload = '/app/corpora/clean/payload_01.json'

    assert os.path.isfile(bench_script), f'The benchmark script {bench_script} is missing.'
    assert os.path.isfile(bench_results), f'The benchmark results file {bench_results} is missing.'
    with open(bench_results, 'r') as f:
        content = f.read().strip()
    assert len(content) > 0, f'The benchmark results file {bench_results} is empty.'

    with open(bench_script, encoding='utf-8') as f:
        bench_source = f.read()
    assert re.search(r'\b(time|SECONDS|date)\b', bench_source), 'benchmark.sh does not measure elapsed time.'

    saved_filter = '/tmp/gateway_filter_under_test.sh'
    calls_file = '/tmp/gateway_benchmark_calls'
    shutil.copy2(filter_path, saved_filter)
    os.unlink(calls_file) if os.path.exists(calls_file) else None
    os.unlink(bench_results)

    wrapper = '''#!/bin/bash
payload=$(mktemp)
cat > "$payload"
if cmp -s "$payload" /app/corpora/clean/payload_01.json; then
    printf 'ok\\n' >> /tmp/gateway_benchmark_calls
else
    printf 'bad\\n' >> /tmp/gateway_benchmark_calls
fi
bash /tmp/gateway_filter_under_test.sh < "$payload"
rc=$?
rm -f "$payload"
exit $rc
'''
    try:
        with open(filter_path, 'w', encoding='utf-8') as f:
            f.write(wrapper)
        os.chmod(filter_path, 0o755)
        started = time.monotonic()
        run = subprocess.run(['bash', bench_script], capture_output=True, text=True, timeout=180)
        wall = time.monotonic() - started
    finally:
        shutil.copy2(saved_filter, filter_path)
        os.chmod(filter_path, 0o755)

    assert run.returncode == 0, f'benchmark.sh failed: stdout={run.stdout!r}, stderr={run.stderr!r}'
    assert os.path.isfile(calls_file), 'benchmark.sh never invoked gateway_filter.sh.'
    with open(calls_file, encoding='utf-8') as f:
        calls = [line.strip() for line in f if line.strip()]
    assert len(calls) == 500, f'benchmark.sh must run exactly 500 iterations; observed {len(calls)}.'
    assert all(call == 'ok' for call in calls), 'Every benchmark iteration must use payload_01.json as stdin.'

    assert os.path.isfile(bench_results), 'benchmark.sh did not create benchmark_results.txt.'
    with open(bench_results, encoding='utf-8') as f:
        generated = f.read().strip()
    assert generated, 'benchmark.sh did not append an elapsed-time result.'
    elapsed = parse_elapsed_seconds(generated)
    assert elapsed is not None and elapsed > 0, f'No valid positive elapsed time was recorded: {generated!r}'
    assert elapsed <= wall * 10 + 1 and elapsed >= max(0.001, wall / 10), (
        f'Recorded elapsed time {elapsed}s is not plausible for the observed {wall:.3f}s run.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
