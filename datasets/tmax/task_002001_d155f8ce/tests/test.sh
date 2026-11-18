#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image

SCRIPT_PATH = Path('/home/user/mlops/generate_artifact.py')
ARCHIVE_SCRIPT = Path('/home/user/mlops/archive.sh')
OUTPUT_DIR = Path('/home/user/mlops/output')
PNG_PATH = OUTPUT_DIR / 'result.png'
ARCHIVE_DIR = Path('/home/user/archive')
TAR_PATH = ARCHIVE_DIR / 'artifacts.tar.gz'


def run_checked(command):
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Command {command!r} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def make_reference_png():
    plt.close('all')
    x = np.linspace(0, 10, 100)
    y = np.sin(x)
    plt.plot(x, y)
    plt.title('Experiment Results')
    stream = io.BytesIO()
    plt.savefig(stream, format='png')
    plt.close('all')
    return stream.getvalue()


def decode_png(data, description):
    try:
        with Image.open(io.BytesIO(data)) as image:
            assert image.format == 'PNG', f"{description} is not a PNG image."
            image.verify()
        with Image.open(io.BytesIO(data)) as image:
            return np.asarray(image.convert('RGBA'), dtype=np.float32) / 255.0
    except Exception as exc:
        raise AssertionError(f"Could not decode {description} as a valid PNG: {exc}") from exc


def test_generate_artifact_script_fixed_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_archive_script_exists_and_executable():
    assert os.path.isfile(ARCHIVE_SCRIPT), f"Script {ARCHIVE_SCRIPT} does not exist."
    assert os.access(ARCHIVE_SCRIPT, os.X_OK), f"Script {ARCHIVE_SCRIPT} is not executable."


def test_result_png_valid_and_contains_expected_plot():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for path in OUTPUT_DIR.iterdir():
        if path.is_file() and path.name.endswith('.png'):
            path.unlink()

    run_checked([str(SCRIPT_PATH)])

    assert os.path.isfile(PNG_PATH), f"{PNG_PATH} does not exist. Did you run the Python script?"

    # Preserve the original size assertion in addition to decoding and content checks.
    size = os.path.getsize(PNG_PATH)
    assert size > 5000, f"{PNG_PATH} is too small ({size} bytes). The plot might still be blank."

    actual = decode_png(PNG_PATH.read_bytes(), str(PNG_PATH))
    expected = decode_png(make_reference_png(), 'the independently generated reference plot')

    assert actual.shape == expected.shape, (
        f"Unexpected image dimensions {actual.shape}; expected {expected.shape}."
    )

    # Compare decoded pixels to a reference independently rendered from the required
    # x values, sine values, and title. This rejects blank or arbitrary large files.
    mean_error = float(np.mean(np.abs(actual - expected)))
    assert mean_error < 0.01, (
        f"The decoded image does not match the required sine plot (mean pixel error {mean_error:.4f})."
    )

    expected_blue = (
        (expected[:, :, 2] - expected[:, :, 0] > 0.15)
        & (expected[:, :, 2] - expected[:, :, 1] > 0.05)
    )
    assert int(expected_blue.sum()) > 100, 'Reference plot unexpectedly lacks a plotted line.'
    line_error = float(np.mean(np.abs(actual[:, :, :3][expected_blue] - expected[:, :, :3][expected_blue])))
    assert line_error < 0.12, (
        f"The sine curve is missing or misplaced (line-region error {line_error:.4f})."
    )


def test_archive_tarball_valid_and_contains_all_png_files():
    # Ensure generation is exercised even if this test is selected independently.
    test_result_png_valid_and_contains_expected_plot()

    # Add unpredictable PNG artifacts so an archive script hard-coded to result.png
    # cannot pass. Appending data after PNG's IEND chunk remains valid PNG data and
    # gives each probe unique bytes for archive-content verification.
    token = secrets.token_hex(12)
    result_data = PNG_PATH.read_bytes()
    probe_names = [f'probe_{token}_a.png', f'probe_{token}_b.png']
    for index, name in enumerate(probe_names):
        (OUTPUT_DIR / name).write_bytes(result_data + f'probe-{token}-{index}'.encode())

    # A non-PNG file must not affect the required PNG set.
    (OUTPUT_DIR / f'ignore_{token}.txt').write_text('not a png')

    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    if TAR_PATH.exists() or TAR_PATH.is_symlink():
        TAR_PATH.unlink()

    run_checked([str(ARCHIVE_SCRIPT)])

    assert os.path.isfile(TAR_PATH), f"{TAR_PATH} does not exist. Did you run the bash script?"
    assert tarfile.is_tarfile(TAR_PATH), f"{TAR_PATH} is not a valid tar file."

    expected_files = {
        path.name: path.read_bytes()
        for path in OUTPUT_DIR.iterdir()
        if path.is_file() and path.name.endswith('.png')
    }
    assert 'result.png' in expected_files
    for name in probe_names:
        assert name in expected_files

    archived_pngs = {}
    with tarfile.open(TAR_PATH, 'r:gz') as tar:
        names = tar.getnames()

        # Preserve the original result.png assertion.
        has_result_png = any(name.endswith('result.png') for name in names)
        assert has_result_png, "result.png is not found in the tarball."

        for name in names:
            # Preserve the original path assertions and additionally reject traversal.
            assert not name.startswith('/'), f"Tarball contains absolute path: {name}"
            assert not name.startswith('home/user'), f"Tarball contains full path hierarchy: {name}"
            parts = PurePosixPath(name).parts
            assert '..' not in parts, f"Tarball contains a parent-directory path: {name}"

        for member in tar.getmembers():
            if not member.isfile() or not member.name.endswith('.png'):
                continue
            normalized = member.name
            while normalized.startswith('./'):
                normalized = normalized[2:]
            parts = PurePosixPath(normalized).parts
            assert len(parts) in (1, 2), f"PNG has an unexpected archived path: {member.name}"
            if len(parts) == 2:
                assert parts[0] == 'output', f"PNG has an unexpected archived path: {member.name}"
            basename = parts[-1]
            assert basename not in archived_pngs, f"PNG is archived more than once: {basename}"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived file: {member.name}"
            archived_pngs[basename] = extracted.read()

    assert set(archived_pngs) == set(expected_files), (
        f"Archive PNG set {sorted(archived_pngs)} does not equal output PNG set {sorted(expected_files)}."
    )
    for name, expected_data in expected_files.items():
        assert archived_pngs[name] == expected_data, f"Archived contents differ for {name}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
