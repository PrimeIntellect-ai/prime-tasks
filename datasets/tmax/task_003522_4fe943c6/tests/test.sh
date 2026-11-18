#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import stat
import bisect
import shutil
import subprocess
from decimal import Decimal, ROUND_HALF_UP
import pytest

HOME = "/home/user"
PROJECT = "/home/user/data_prep"
SCRIPT = "/home/user/run_pipeline.sh"
RESULTS = "/home/user/results.json"
RAW = "/home/user/raw_data.csv"
REF = "/home/user/ref_data.csv"

def ks_2samp_manual(data1, data2):
    n1 = len(data1)
    n2 = len(data2)
    data1.sort()
    data2.sort()

    data_all = sorted(data1 + data2)

    max_diff = 0.0
    for val in data_all:
        cdf1 = bisect.bisect_right(data1, val) / n1
        cdf2 = bisect.bisect_right(data2, val) / n2
        diff = abs(cdf1 - cdf2)
        if diff > max_diff:
            max_diff = diff

    return max_diff

def get_expected_results():
    raw_data = []
    with open('/home/user/raw_data.csv', 'r') as f:
        next(f)
        for line in f:
            if line.strip():
                raw_data.append(float(line.strip()))

    ref_data = []
    with open('/home/user/ref_data.csv', 'r') as f:
        next(f)
        for line in f:
            if line.strip():
                ref_data.append(float(line.strip()))

    min_ks = float('inf')
    best_alpha = None
    best_beta = None

    for a in range(21):
        alpha = a * 0.05
        for b in range(21):
            beta = b * 0.10

            y = [alpha * (x ** 2) + beta * x for x in raw_data]
            ks = ks_2samp_manual(y, ref_data)

            if ks < min_ks - 1e-9:
                min_ks = ks
                best_alpha = alpha
                best_beta = beta

    return best_alpha, best_beta, min_ks

def run_checked(command, cwd=HOME):
    return subprocess.run(
        command, cwd=cwd, check=True, timeout=180,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )

def load_and_check_current_results():
    assert os.path.isfile(RESULTS), f"Expected results file {RESULTS} to exist."
    with open(RESULTS, 'r') as f:
        results = json.load(f)
    expected_alpha, expected_beta, expected_ks = get_expected_results()
    rounded_ks = float(Decimal(str(expected_ks)).quantize(
        Decimal('0.000001'), rounding=ROUND_HALF_UP))
    assert abs(results["alpha"] - expected_alpha) < 1e-9
    assert abs(results["beta"] - expected_beta) < 1e-9
    assert abs(results["ks_stat"] - rounded_ks) < 1e-9

def write_probe(raw, ref):
    with open(RAW, 'w') as f:
        f.write('x\n')
        for value in raw:
            f.write(f'{value:.17g}\n')
    with open(REF, 'w') as f:
        f.write('z\n')
        for value in ref:
            f.write(f'{value:.17g}\n')
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

def cargo_binary_paths():
    metadata = json.loads(run_checked([
        'cargo', 'metadata', '--format-version', '1', '--no-deps',
        '--manifest-path', os.path.join(PROJECT, 'Cargo.toml')
    ], cwd=PROJECT).stdout)
    manifest = os.path.realpath(os.path.join(PROJECT, 'Cargo.toml'))
    packages = [p for p in metadata['packages']
                if os.path.realpath(p['manifest_path']) == manifest]
    assert packages, 'Cargo metadata did not contain the submitted project.'
    names = []
    for package in packages:
        for target in package['targets']:
            if 'bin' in target.get('kind', []):
                names.append(target['name'])
    assert names, 'The Cargo project has no Rust binary target.'
    target_dir = metadata['target_directory']
    return [os.path.join(target_dir, 'release', name) for name in names]

def test_rust_binary_project_exists():
    assert os.path.isdir(PROJECT), f"Expected Rust project {PROJECT} to exist."
    assert os.path.isfile(os.path.join(PROJECT, 'Cargo.toml')), 'Missing Cargo.toml.'
    assert os.path.isfile(os.path.join(PROJECT, 'src', 'main.rs')), 'Missing src/main.rs.'
    cargo_binary_paths()

def test_run_pipeline_exists_and_executable():
    path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(path), f"Expected script {path} to exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Expected script {path} to be executable."

def test_pipeline_runs_on_original_data():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    run_checked([SCRIPT])
    assert os.path.isfile(RESULTS), 'run_pipeline.sh did not generate results.json.'

def test_results_json_exists():
    path = "/home/user/results.json"
    assert os.path.isfile(path), f"Expected results file {path} to exist."

def test_results_json_content():
    path = "/home/user/results.json"
    assert os.path.isfile(path), f"Expected results file {path} to exist."

    with open(path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse {path} as JSON.")

    assert "alpha" in results, "Missing 'alpha' in results.json"
    assert "beta" in results, "Missing 'beta' in results.json"
    assert "ks_stat" in results, "Missing 'ks_stat' in results.json"

    expected_alpha, expected_beta, expected_ks = get_expected_results()

    # Check values with tolerances
    assert abs(results["alpha"] - expected_alpha) < 1e-5, \
        f"Expected alpha ~ {expected_alpha:.2f}, got {results['alpha']}"
    assert abs(results["beta"] - expected_beta) < 1e-5, \
        f"Expected beta ~ {expected_beta:.2f}, got {results['beta']}"
    assert abs(results["ks_stat"] - expected_ks) < 1e-5, \
        f"Expected ks_stat ~ {expected_ks:.6f}, got {results['ks_stat']}"

def test_script_and_compiled_rust_program_handle_new_inputs():
    saved = {}
    for path in (RAW, REF, RESULTS):
        saved[path] = open(path, 'rb').read() if os.path.exists(path) else None

    try:
        raw1 = [-3.25, -1.5, -0.2, 0.4, 1.1, 2.7, 4.05]
        ref1 = [0.60 * x * x + 0.30 * x for x in raw1]
        write_probe(raw1, ref1)
        run_checked([SCRIPT])
        load_and_check_current_results()

        run_checked([
            'cargo', 'build', '--release', '--bins',
            '--manifest-path', os.path.join(PROJECT, 'Cargo.toml')
        ], cwd=PROJECT)
        binaries = cargo_binary_paths()
        assert all(os.path.isfile(path) for path in binaries), \
            'Cargo did not produce the expected release binary target(s).'

        raw2 = [-4.1, -2.3, -0.75, 0.15, 0.9, 1.8, 3.2, 5.0]
        ref2 = [0.15 * x * x + 1.70 * x for x in raw2]
        matched = False
        errors = []
        for binary in binaries:
            write_probe(raw2, ref2)
            try:
                run_checked([binary])
                load_and_check_current_results()
                matched = True
                break
            except Exception as exc:
                errors.append(f'{binary}: {exc}')
        assert matched, 'No compiled Rust binary produced correct results: ' + '; '.join(errors)
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, 'wb') as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
