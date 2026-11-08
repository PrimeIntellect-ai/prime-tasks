#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import pathlib
import pwd
import random
import subprocess
import tempfile

DATA_FILE = pathlib.Path('/home/user/sensor_data.csv')
RESULTS_FILE = pathlib.Path('/home/user/results.json')
ORIGINAL_DATA = '''alpha,beta
2.0,10.0
4.0,12.0
NA,9.0
6.0,14.0
8.0,16.0
10.0,18.0
invalid,20.0
100.0,22.0
'''


def expected_results(csv_text):
    rows = []
    for row in csv.DictReader(csv_text.splitlines()):
        try:
            alpha = float(row['alpha'])
            beta = float(row['beta'])
        except (KeyError, TypeError, ValueError):
            continue
        if math.isfinite(alpha) and math.isfinite(beta):
            rows.append((alpha, beta))

    assert len(rows) >= 2
    alpha_mean = sum(a for a, _ in rows) / len(rows)
    alpha_std = math.sqrt(sum((a - alpha_mean) ** 2 for a, _ in rows) / (len(rows) - 1))
    cleaned = [(a, b) for a, b in rows if abs(a - alpha_mean) <= 2.0 * alpha_std]
    assert len(cleaned) >= 2

    clean_alpha_mean = sum(a for a, _ in cleaned) / len(cleaned)
    clean_beta_mean = sum(b for _, b in cleaned) / len(cleaned)
    covariance = sum((a - clean_alpha_mean) * (b - clean_beta_mean) for a, b in cleaned) / (len(cleaned) - 1)

    posterior_precision = 1.0 / 2.0 + len(cleaned) / 4.0
    posterior_mean = ((10.0 / 2.0) + sum(b for _, b in cleaned) / 4.0) / posterior_precision
    return round(covariance, 4), round(posterior_mean, 4)


def generated_dataset(seed):
    rng = random.Random(seed)
    lines = ['alpha,beta']
    for i in range(7):
        alpha = round(rng.uniform(-20.0, 30.0) + i * 1.7, 5)
        beta = round(rng.uniform(-15.0, 25.0) - alpha * 0.37, 5)
        lines.append(f'{alpha},{beta}')
    lines.extend([
        f'{1000000.0 + seed},{rng.uniform(-50.0, 50.0):.5f}',
        'invalid,12.5',
        '3.5,',
        ',8.0',
    ])
    return '\n'.join(lines) + '\n'


def discover_runners(tmpdir):
    roots = [pathlib.Path('/home/user')]
    for optional in ('/workspace', '/root'):
        path = pathlib.Path(optional)
        if path.exists():
            roots.append(path)

    ignored_parts = {'.cargo', '.rustup', 'target', '.git'}
    manifests = []
    rust_sources = []
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in ignored_parts]
            current = pathlib.Path(dirpath)
            if 'Cargo.toml' in filenames:
                manifests.append(current / 'Cargo.toml')
            for filename in filenames:
                if filename.endswith('.rs'):
                    rust_sources.append(current / filename)

    runners = []
    seen_manifests = set()
    for manifest in manifests:
        resolved = manifest.resolve()
        if resolved in seen_manifests:
            continue
        seen_manifests.add(resolved)
        runners.append({
            'name': f'Cargo project {manifest}',
            'cmd': ['cargo', 'run', '--quiet', '--manifest-path', str(manifest)],
            'cwd': str(manifest.parent),
        })

    manifest_dirs = [m.parent.resolve() for m in manifests]
    for index, source in enumerate(rust_sources):
        resolved_source = source.resolve()
        if any(project_dir == resolved_source.parent or project_dir in resolved_source.parents for project_dir in manifest_dirs):
            continue
        output = pathlib.Path(tmpdir) / f'rust_submission_{index}'
        compile_result = subprocess.run(
            ['rustc', str(source), '-O', '-o', str(output)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        if compile_result.returncode == 0:
            runners.append({
                'name': f'standalone Rust source {source}',
                'cmd': [str(output)],
                'cwd': str(source.parent),
            })
    return runners


def run_as_user(runner):
    user = pwd.getpwnam('user')

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['CARGO_HOME'] = '/home/user/.cargo'
    return subprocess.run(
        runner['cmd'],
        cwd=runner['cwd'],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
        preexec_fn=demote,
    )


def read_and_check_results(expected_covariance, expected_posterior):
    assert RESULTS_FILE.exists(), f'The file {RESULTS_FILE} does not exist.'
    assert RESULTS_FILE.is_file(), f'The path {RESULTS_FILE} is not a file.'
    try:
        with RESULTS_FILE.open('r') as handle:
            data = json.load(handle)
    except json.JSONDecodeError:
        assert False, f'The file {RESULTS_FILE} does not contain valid JSON.'

    assert 'covariance' in data, "The key 'covariance' is missing from the JSON results."
    assert 'posterior_mean_beta' in data, "The key 'posterior_mean_beta' is missing from the JSON results."
    try:
        covariance = float(data['covariance'])
        posterior = float(data['posterior_mean_beta'])
    except (TypeError, ValueError):
        assert False, 'The values in the JSON results could not be parsed as floats.'

    assert math.isfinite(covariance) and math.isfinite(posterior)
    assert math.isclose(covariance, expected_covariance, abs_tol=1e-3), (
        f'Expected covariance to be approximately {expected_covariance}, but got {covariance}.'
    )
    assert math.isclose(posterior, expected_posterior, abs_tol=1e-3), (
        f'Expected posterior_mean_beta to be approximately {expected_posterior}, but got {posterior}.'
    )


def runner_passes(runner, datasets):
    for csv_text in datasets:
        DATA_FILE.write_text(csv_text)
        if RESULTS_FILE.exists():
            RESULTS_FILE.unlink()
        result = run_as_user(runner)
        if result.returncode != 0:
            return False
        try:
            read_and_check_results(*expected_results(csv_text))
        except AssertionError:
            return False
    return True


def test_rust_program_computes_results_from_sensor_data():
    # Preserve and explicitly retain the original verifier's expected-value assertions.
    original_expected = expected_results(ORIGINAL_DATA)
    assert math.isclose(original_expected[0], 10.0, abs_tol=1e-3)
    assert math.isclose(original_expected[1], 12.8571, abs_tol=1e-3)

    datasets = [ORIGINAL_DATA, generated_dataset(7319), generated_dataset(19427)]
    original_on_disk = DATA_FILE.read_text() if DATA_FILE.exists() else ORIGINAL_DATA

    with tempfile.TemporaryDirectory(prefix='rust_verify_') as tmpdir:
        runners = discover_runners(tmpdir)
        assert runners, 'No compilable Rust program or Cargo project was found.'

        successful = None
        try:
            for runner in runners:
                if runner_passes(runner, datasets):
                    successful = runner
                    break
            assert successful is not None, 'No Rust program correctly processed the original and held-out sensor datasets.'

            # Leave the required final files corresponding to the original task input.
            DATA_FILE.write_text(ORIGINAL_DATA)
            if RESULTS_FILE.exists():
                RESULTS_FILE.unlink()
            result = run_as_user(successful)
            assert result.returncode == 0, result.stderr
            read_and_check_results(10.0, 12.8571)
        finally:
            DATA_FILE.write_text(original_on_disk)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
