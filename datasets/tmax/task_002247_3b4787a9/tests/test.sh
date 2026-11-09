#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import tempfile


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10, **kwargs)


def test_json2csv_installed_and_package_repaired():
    bin_path = '/home/user/.local/bin/json2csv'
    source_path = '/app/json2csv-schema-1.2/json2csv.sh'

    assert os.path.isfile(bin_path), f"{bin_path} is missing. Did you install the package?"
    st = os.stat(bin_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{bin_path} is not executable."

    assert os.path.isfile(source_path), f"{source_path} is missing."
    source_stat = os.stat(source_path)
    assert bool(source_stat.st_mode & stat.S_IXUSR), "Vendored json2csv.sh is not executable."
    with open(source_path, 'rb') as f:
        assert b'\r\n' not in f.read(), "Vendored json2csv.sh still has CRLF line endings."

    with tempfile.TemporaryDirectory() as td:
        prefix = os.path.join(td, 'prefix')
        proc = run(
            ['make', 'install', f'PREFIX={prefix}'],
            cwd='/app/json2csv-schema-1.2'
        )
        assert proc.returncode == 0, f"make install failed: {proc.stdout}\n{proc.stderr}"

        fresh_bin = os.path.join(prefix, 'bin', 'json2csv')
        assert os.path.isfile(fresh_bin), "make install did not install PREFIX/bin/json2csv."
        assert os.access(fresh_bin, os.X_OK), "Freshly installed json2csv is not executable."

        records = [
            {'artifact_id': 'CHECK-17', 'run_id': 'x1', 'status': 'SUCCESS', 'latency_ms': 0},
            {'artifact_id': 'CHECK-29', 'run_id': 'x2', 'status': 'FAILED', 'latency_ms': 731},
            {'artifact_id': 'CHECK-17', 'run_id': 'x3', 'status': 'TIMEOUT', 'latency_ms': 44},
        ]
        input_path = os.path.join(td, 'input.jsonl')
        with open(input_path, 'w') as f:
            for record in records:
                f.write(json.dumps(record) + '\n')

        expected = (
            'artifact_id,run_id,status,latency_ms\n'
            'CHECK-17,x1,SUCCESS,0\n'
            'CHECK-29,x2,FAILED,731\n'
            'CHECK-17,x3,TIMEOUT,44\n'
        )

        for candidate in (fresh_bin, bin_path):
            env = os.environ.copy()
            env['ENFORCE_STRICT_SCHEMA'] = '1'
            proc = run([candidate, input_path], env=env)
            assert proc.returncode == 0, f"{candidate} failed: {proc.stderr}"
            assert proc.stdout == expected, f"{candidate} produced incorrect CSV output."

            env.pop('ENFORCE_STRICT_SCHEMA', None)
            proc = run([candidate, input_path], env=env)
            assert proc.returncode != 0, f"{candidate} accepted input without strict schema enforcement."


def test_artifacts_csv_created():
    csv_path = '/home/user/artifacts.csv'
    assert os.path.isfile(csv_path), f"{csv_path} is missing."
    with open(csv_path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 7, "artifacts.csv should have 7 lines (1 header + 6 data rows)."
    assert lines[0] == "artifact_id,run_id,status,latency_ms", "artifacts.csv header is incorrect."
    assert "ART-101,r1,SUCCESS,45" in lines, "artifacts.csv is missing expected data rows."

    assert lines == [
        'artifact_id,run_id,status,latency_ms',
        'ART-101,r1,SUCCESS,45',
        'ART-101,r2,SUCCESS,55',
        'ART-101,r3,FAILED,40',
        'ART-102,r4,SUCCESS,100',
        'ART-102,r5,SUCCESS,90',
        'ART-103,r6,SUCCESS,10',
    ], "artifacts.csv is not the complete conversion of raw_experiments.jsonl."


def test_bayesian_benchmark_script_exists():
    script_path = '/home/user/bayesian_benchmark.sh'
    assert os.path.isfile(script_path), f"{script_path} is missing."


def expected_mean(rows, artifact, threshold):
    matching = [row for row in rows if row[0] == artifact]
    successes = sum(
        1 for row in matching
        if row[2] == 'SUCCESS' and row[3] <= threshold
    )
    failures = len(matching) - successes
    return f"{(2 + successes) / (4 + successes + failures):.4f}\n"


def invoke_benchmark(artifact, threshold):
    proc = run([
        '/bin/bash', '/home/user/bayesian_benchmark.sh', artifact, str(threshold)
    ])
    assert proc.returncode == 0, (
        f"Agent script failed for input {artifact} {threshold}. Error: {proc.stderr}"
    )
    return proc.stdout


def test_fuzz_equivalence():
    rows = [
        ('ART-101', 'r1', 'SUCCESS', 45),
        ('ART-101', 'r2', 'SUCCESS', 55),
        ('ART-101', 'r3', 'FAILED', 40),
        ('ART-102', 'r4', 'SUCCESS', 100),
        ('ART-102', 'r5', 'SUCCESS', 90),
        ('ART-103', 'r6', 'SUCCESS', 10),
    ]
    rng = random.Random(42)
    artifacts = ['ART-101', 'ART-102', 'ART-103']

    for _ in range(100):
        artifact = rng.choice(artifacts)
        threshold = rng.randint(10, 150)
        actual = invoke_benchmark(artifact, threshold)
        expected = expected_mean(rows, artifact, threshold)
        assert actual == expected, (
            f"Mismatch for artifact_id={artifact}, latency_threshold={threshold}: "
            f"expected {expected!r}, got {actual!r}"
        )


def test_benchmark_on_verifier_generated_data():
    csv_path = '/home/user/artifacts.csv'
    with open(csv_path, 'rb') as f:
        original = f.read()

    rng = random.SystemRandom()
    artifacts = [f'FUZZ-{i}-{rng.randrange(100000, 999999)}' for i in range(8)]
    statuses = ['SUCCESS', 'FAILED', 'TIMEOUT', 'success', 'SUCCESS ']
    rows = []
    for i in range(240):
        rows.append((
            rng.choice(artifacts),
            f'generated{i}',
            rng.choice(statuses),
            rng.randint(0, 500),
        ))

    try:
        with open(csv_path, 'w') as f:
            f.write('artifact_id,run_id,status,latency_ms\n')
            for artifact, run_id, status, latency in rows:
                f.write(f'{artifact},{run_id},{status},{latency}\n')

        query_artifacts = artifacts + [f'ABSENT-{rng.randrange(100000, 999999)}']
        for _ in range(180):
            artifact = rng.choice(query_artifacts)
            if rng.randrange(3) == 0:
                threshold = rng.choice(rows)[3]
            else:
                threshold = rng.randint(-20, 550)
            actual = invoke_benchmark(artifact, threshold)
            expected = expected_mean(rows, artifact, threshold)
            assert actual == expected, (
                f"Mismatch on generated data for artifact_id={artifact}, "
                f"latency_threshold={threshold}: expected {expected!r}, got {actual!r}"
            )
    finally:
        with open(csv_path, 'wb') as f:
            f.write(original)
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
