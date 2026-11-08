#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import secrets
import shutil
import struct
import subprocess
import tarfile
import tempfile
from pathlib import Path

REPORT_PATH = Path('/home/user/metrics/mse_report.txt')
ARCHIVE_PATH = Path('/home/user/archive/experiment_run.tar.gz')
PROJECT_PATH = Path('/home/user/evaluator')
BASELINE_PATH = Path('/home/user/artifacts/baseline.bin')
EXPERIMENT_PATH = Path('/home/user/artifacts/experiment.bin')
COUNT = 1_000_000
FILE_SIZE = COUNT * 8
PACK = struct.Struct('<d')


def test_mse_report_content():
    report_path = str(REPORT_PATH)
    assert os.path.exists(report_path), f"MSE report not found at {report_path}"
    assert os.path.isfile(report_path), f"MSE report path {report_path} is not a file"

    with open(report_path, 'r') as f:
        content = f.read().strip()

    expected_mse = "0.000600"
    assert content == expected_mse, f"Incorrect MSE in report: expected {expected_mse}, got {content}"


def _expected_artifact_hashes():
    baseline_hash = hashlib.sha256()
    experiment_hash = hashlib.sha256()
    base_buffer = bytearray()
    experiment_buffer = bytearray()

    for i in range(COUNT):
        base_val = i * 0.001
        error = (i % 5) * 0.01
        exp_val = base_val + error
        base_buffer.extend(PACK.pack(base_val))
        experiment_buffer.extend(PACK.pack(exp_val))

        if len(base_buffer) >= 8 * 8192:
            baseline_hash.update(base_buffer)
            experiment_hash.update(experiment_buffer)
            base_buffer.clear()
            experiment_buffer.clear()

    baseline_hash.update(base_buffer)
    experiment_hash.update(experiment_buffer)
    return baseline_hash.hexdigest(), experiment_hash.hexdigest()


def _member_digest(tar, member):
    assert member.isfile(), f"Archive member {member.name} is not a regular file"
    assert member.size == FILE_SIZE, (
        f"Archive member {member.name} has size {member.size}, expected {FILE_SIZE}"
    )
    extracted = tar.extractfile(member)
    assert extracted is not None, f"Could not read archive member {member.name}"
    digest = hashlib.sha256()
    while True:
        chunk = extracted.read(1024 * 1024)
        if not chunk:
            break
        digest.update(chunk)
    return digest.hexdigest()


def test_archive_exists_and_contents():
    archive_path = str(ARCHIVE_PATH)
    assert os.path.exists(archive_path), f"Archive not found at {archive_path}"
    assert os.path.isfile(archive_path), f"Archive path {archive_path} is not a file"

    assert tarfile.is_tarfile(archive_path), f"File at {archive_path} is not a valid tar archive"

    with tarfile.open(archive_path, 'r:gz') as tar:
        members = tar.getnames()

        # Preserve the original checks.
        has_baseline = any(m.endswith('baseline.bin') for m in members)
        has_experiment = any(m.endswith('experiment.bin') for m in members)
        assert has_baseline, "baseline.bin missing from the archive"
        assert has_experiment, "experiment.bin missing from the archive"
        for m in members:
            assert not m.startswith('/'), f"Archive member {m} contains an absolute path"

        # The requested files must be top-level regular files containing the
        # exact supplied prediction artifacts, not empty or fabricated entries.
        baseline_members = [m for m in tar.getmembers() if m.name in ('baseline.bin', './baseline.bin')]
        experiment_members = [m for m in tar.getmembers() if m.name in ('experiment.bin', './experiment.bin')]
        assert baseline_members, "baseline.bin is not stored as a top-level file"
        assert experiment_members, "experiment.bin is not stored as a top-level file"

        expected_baseline, expected_experiment = _expected_artifact_hashes()
        assert any(_member_digest(tar, m) == expected_baseline for m in baseline_members), \
            "Archived baseline.bin does not match the supplied prediction artifact"
        assert any(_member_digest(tar, m) == expected_experiment for m in experiment_members), \
            "Archived experiment.bin does not match the supplied prediction artifact"


def test_rust_project_computes_unseen_input():
    assert PROJECT_PATH.is_dir(), f"Rust project not found at {PROJECT_PATH}"
    manifest = PROJECT_PATH / 'Cargo.toml'
    assert manifest.is_file(), f"Cargo manifest not found at {manifest}"
    assert any(PROJECT_PATH.rglob('*.rs')), "Rust project contains no Rust source files"

    env = os.environ.copy()
    env['CARGO_NET_OFFLINE'] = 'true'
    metadata_result = subprocess.run(
        ['cargo', 'metadata', '--offline', '--no-deps', '--format-version', '1',
         '--manifest-path', str(manifest)],
        cwd=str(PROJECT_PATH), env=env, text=True, capture_output=True, timeout=60
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    packages = [p for p in metadata['packages'] if p['name'] == 'evaluator']
    assert packages, "Cargo package is not named evaluator"
    assert any('bin' in target.get('kind', []) for p in packages for target in p['targets']), \
        "The evaluator package has no Rust binary target"

    with tempfile.TemporaryDirectory() as backup_dir:
        backup_dir = Path(backup_dir)
        saved = {}
        for path in (BASELINE_PATH, EXPERIMENT_PATH, REPORT_PATH):
            if path.is_file():
                backup = backup_dir / path.name
                shutil.copy2(path, backup)
                saved[path] = backup

        try:
            BASELINE_PATH.parent.mkdir(parents=True, exist_ok=True)
            REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)

            rng = random.Random(secrets.randbits(128))
            total_squared_units = 0
            with BASELINE_PATH.open('wb') as baseline, EXPERIMENT_PATH.open('wb') as experiment:
                base_buffer = bytearray()
                experiment_buffer = bytearray()
                for _ in range(COUNT):
                    base = rng.randrange(-1000, 1001)
                    delta_units = rng.randrange(-8, 9)
                    total_squared_units += delta_units * delta_units
                    base_buffer.extend(PACK.pack(float(base)))
                    experiment_buffer.extend(PACK.pack(base + delta_units / 16.0))
                    if len(base_buffer) >= 8 * 8192:
                        baseline.write(base_buffer)
                        experiment.write(experiment_buffer)
                        base_buffer.clear()
                        experiment_buffer.clear()
                baseline.write(base_buffer)
                experiment.write(experiment_buffer)

            expected = f"{total_squared_units / (256.0 * COUNT):.6f}"
            if REPORT_PATH.exists():
                REPORT_PATH.unlink()

            subprocess.run(
                ['cargo', 'clean', '--manifest-path', str(manifest)],
                cwd=str(PROJECT_PATH), env=env, text=True, capture_output=True,
                timeout=60, check=True
            )
            result = subprocess.run(
                ['cargo', 'run', '--offline', '--quiet', '--manifest-path', str(manifest),
                 '--bin', 'evaluator'],
                cwd=str(PROJECT_PATH), env=env, text=True, capture_output=True, timeout=180
            )
            assert result.returncode == 0, f"Rust evaluator failed: {result.stderr}"
            assert REPORT_PATH.is_file(), "Running the Rust evaluator did not create mse_report.txt"
            actual = REPORT_PATH.read_text().strip()
            assert actual == expected, (
                f"Rust evaluator failed an unseen input: expected {expected}, got {actual}"
            )
        finally:
            for path in (BASELINE_PATH, EXPERIMENT_PATH, REPORT_PATH):
                if path.exists() or path.is_symlink():
                    path.unlink()
                if path in saved:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(saved[path], path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
