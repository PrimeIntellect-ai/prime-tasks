#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import subprocess
from pathlib import Path

PIPELINE = Path('/home/user/pipeline')
CARGO_TOML = PIPELINE / 'Cargo.toml'
FEATURES = Path('/home/user/features.csv')
LABELS = Path('/home/user/labels.csv')
POSTERIOR = Path('/home/user/posterior.json')


def test_rust_project_exists():
    pipeline_dir = '/home/user/pipeline'
    assert os.path.isdir(pipeline_dir), f'Directory {pipeline_dir} is missing. Did you initialize the Rust project?'

    cargo_toml = os.path.join(pipeline_dir, 'Cargo.toml')
    assert os.path.isfile(cargo_toml), f'File {cargo_toml} is missing. Ensure the project is a valid Rust Cargo project.'


def test_posterior_json_exists_and_correct():
    posterior_file = '/home/user/posterior.json'
    assert os.path.isfile(posterior_file), f'File {posterior_file} is missing. Did you generate the output?'

    with open(posterior_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            raise AssertionError(f'File {posterior_file} is not a valid JSON file.')

    assert 'alpha' in data, f"'alpha' key missing in {posterior_file}"
    assert 'beta' in data, f"'beta' key missing in {posterior_file}"

    assert isinstance(data['alpha'], int), "'alpha' must be an integer"
    assert isinstance(data['beta'], int), "'beta' must be an integer"

    assert data['alpha'] == 3, f"Expected alpha to be 3, got {data['alpha']}"
    assert data['beta'] == 2, f"Expected beta to be 2, got {data['beta']}"


def validate_project_and_polars_source():
    rust_files = list((PIPELINE / 'src').rglob('*.rs'))
    assert rust_files, 'The Cargo project has no Rust source files under src/'
    source = '\n'.join(p.read_text(errors='replace') for p in rust_files)
    assert source.strip(), 'The Rust source files are empty'

    result = subprocess.run(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps', '--manifest-path', str(CARGO_TOML)],
        cwd=PIPELINE, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, f'Cargo metadata failed; this is not a valid Cargo project:\n{result.stderr}'
    metadata = json.loads(result.stdout)
    manifest = str(CARGO_TOML.resolve())
    packages = [p for p in metadata.get('packages', []) if str(Path(p['manifest_path']).resolve()) == manifest]
    assert packages, 'Cargo metadata did not contain the pipeline package'
    package = packages[0]
    assert any(t.get('kind') and 'bin' in t['kind'] for t in package.get('targets', [])), 'The pipeline package has no Rust binary target'
    assert any(d.get('name') == 'polars' for d in package.get('dependencies', [])), 'Cargo.toml must declare the polars crate as a dependency'

    assert re.search(r'polars\s*::', source), 'Rust source does not use the polars crate'
    assert re.search(r'CsvReader|LazyCsvReader|CsvReadOptions|scan_csv|read_csv', source), 'Rust source does not use a Polars CSV reader'
    assert re.search(r'(?:^|\.)\s*(?:join|inner_join|left_join|full_join)\s*\(', source, re.M), 'Rust source does not perform a Polars join'
    assert re.search(r'\.\s*filter\s*\(', source), 'Rust source does not perform the required Polars filtering'
    assert re.search(r'drop_nulls|is_not_null', source), 'Rust source does not explicitly remove null label rows'
    assert re.search(r'DataType\s*::\s*(?:Int8|Int16|Int32|Int64)|\.\s*i(?:8|16|32|64)\s*\(|is_integer', source), 'Rust source does not ensure or access label as an integer-typed Polars column'


def run_pipeline():
    if POSTERIOR.exists():
        POSTERIOR.unlink()
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(CARGO_TOML)],
        cwd=PIPELINE, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600
    )
    assert result.returncode == 0, f'The Rust pipeline failed to run:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    assert POSTERIOR.is_file(), 'Running the Rust pipeline did not create /home/user/posterior.json'


def read_posterior(expected_alpha, expected_beta):
    try:
        data = json.loads(POSTERIOR.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError('The executed pipeline produced invalid JSON') from exc
    assert isinstance(data, dict), 'The executed pipeline output must be a JSON object'
    assert set(data) == {'alpha', 'beta'}, 'The executed pipeline output must contain exactly alpha and beta'
    assert type(data['alpha']) is int and type(data['beta']) is int, 'Posterior parameters must be JSON integers'
    assert data == {'alpha': expected_alpha, 'beta': expected_beta}, (
        f'Pipeline produced {data}, expected alpha={expected_alpha}, beta={expected_beta}'
    )


def make_case(rng):
    while True:
        ids = rng.sample(range(10000, 90000), 12)
        feature_values = [0.1, 0.2, 0.49, 0.5, 0.5001, 0.55, 0.61, 0.72, 0.83, 0.94, 0.99, 0.4]
        rng.shuffle(feature_values)
        labels = {}
        for uid in ids:
            choice = rng.randrange(5)
            labels[uid] = None if choice == 0 else rng.randrange(2)

        included = [labels[uid] for uid, value in zip(ids, feature_values)
                    if value > 0.5 and labels[uid] is not None]
        successes = sum(v == 1 for v in included)
        failures = sum(v == 0 for v in included)
        expected = (1 + successes, 1 + failures)
        if successes > 0 and failures > 0 and expected != (3, 2) and any(v is None for v in labels.values()):
            break

    feature_rows = list(zip(ids, feature_values))
    label_rows = list(labels.items())
    rng.shuffle(feature_rows)
    rng.shuffle(label_rows)

    feature_text = 'user_id,feature_a\n' + ''.join(f'{uid},{value}\n' for uid, value in feature_rows)
    label_text = 'user_id,label\n' + ''.join(
        f'{uid},{"" if label is None else label}\n' for uid, label in label_rows
    )
    # Add a label with no matching feature to ensure the result comes from the join.
    label_text += f'{rng.randrange(90001, 99999)},{rng.randrange(2)}\n'
    return feature_text, label_text, expected


def main():
    test_rust_project_exists()
    validate_project_and_polars_source()

    original_features = FEATURES.read_bytes()
    original_labels = LABELS.read_bytes()
    rng = random.SystemRandom()
    dynamic_error = None

    try:
        expectations = []
        for _ in range(2):
            feature_text, label_text, expected = make_case(rng)
            # Ensure the two runtime cases do not accidentally have the same answer.
            while expected in expectations:
                feature_text, label_text, expected = make_case(rng)
            expectations.append(expected)
            FEATURES.write_text(feature_text)
            LABELS.write_text(label_text)
            run_pipeline()
            read_posterior(*expected)
    except Exception as exc:
        dynamic_error = exc
    finally:
        FEATURES.write_bytes(original_features)
        LABELS.write_bytes(original_labels)

    # Re-run on the supplied data, then retain all assertions from the original verifier.
    run_pipeline()
    test_posterior_json_exists_and_correct()

    if dynamic_error is not None:
        raise AssertionError(f'Pipeline failed behavioral tests on verifier-generated CSV inputs: {dynamic_error}') from dynamic_error


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
