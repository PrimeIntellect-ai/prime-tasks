#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import cv2
import numpy as np

HOME = Path('/home/user')
FRAMES = HOME / 'frames'
TRAJECTORY = HOME / 'extracted_trajectory.csv'
PIPELINE = HOME / 'pipeline.sh'
EXTRACT_SOURCE = HOME / 'extract_tracking.c'
FILTER_SOURCE = HOME / 'artifact_filter.c'
FILTER_BINARY = HOME / 'artifact_filter'


def run(cmd, **kwargs):
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('text', True)
    kwargs.setdefault('timeout', 120)
    return subprocess.run(cmd, **kwargs)


def natural_key(path):
    return [int(part) if part.isdigit() else part for part in re.split(r'(\d+)', Path(path).name)]


def read_csv(path):
    with open(path, newline='') as f:
        return list(csv.reader(f))


def classification_map(stdout, expected_names):
    result = {}
    bad_classification_lines = []
    pattern = re.compile(r'^([^/\r\n:]+\.csv): (CLEAN|EVIL)$')
    for raw in stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        match = pattern.fullmatch(line)
        if match:
            name, label = match.groups()
            assert name in expected_names, f'Pipeline reported unexpected CSV {name!r}: {line!r}'
            assert name not in result, f'Pipeline reported {name!r} more than once'
            result[name] = label
        elif 'CLEAN' in line or 'EVIL' in line:
            bad_classification_lines.append(line)
    assert not bad_classification_lines, f'Malformed classification output: {bad_classification_lines}'
    return result


def write_csv(path, points):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['frame_id', 'x', 'y'])
        for i, (x, y) in enumerate(points):
            writer.writerow([i, x, y])


def write_pgm(path, image):
    height, width = image.shape
    with open(path, 'wb') as f:
        f.write(f'P5\n{width} {height}\n255\n'.encode('ascii'))
        f.write(image.tobytes())


def test_extracted_trajectory_and_video_frames():
    # Preserve all original shape and syntax assertions.
    assert TRAJECTORY.exists(), f'Missing extracted trajectory CSV at {TRAJECTORY}'
    rows = read_csv(TRAJECTORY)
    assert len(rows) > 0, 'CSV file is empty'
    assert [c.strip() for c in rows[0]] == ['frame_id', 'x', 'y']
    data_rows = rows[1:]
    assert len(data_rows) == 100, f'Expected 100 data rows, got {len(data_rows)}'
    for i, row in enumerate(data_rows):
        assert len(row) == 3, f'Row {i} has incorrect number of columns: {row}'
        frame_id, x, y = row
        assert frame_id.strip().isdigit(), f'Row {i} frame_id is not an integer: {frame_id}'
        assert x.strip().lstrip('-').isdigit(), f'Row {i} x is not an integer: {x}'
        assert y.strip().lstrip('-').isdigit(), f'Row {i} y is not an integer: {y}'

    assert FRAMES.exists(), f'Missing frames directory at {FRAMES}'
    submitted = sorted(FRAMES.glob('*.pgm'), key=natural_key)
    assert len(submitted) == 100, f'Expected 100 PGM files in {FRAMES}, got {len(submitted)}'

    # Independently extract the supplied video and ensure the submitted PGM files
    # really are its frames, rather than fabricated images.
    with tempfile.TemporaryDirectory() as reference_dir:
        reference_pattern = str(Path(reference_dir) / 'reference_%03d.pgm')
        ffmpeg = run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
            '-i', '/app/experiment.mp4', '-vf', 'format=gray', reference_pattern
        ])
        assert ffmpeg.returncode == 0, f'Independent ffmpeg extraction failed: {ffmpeg.stderr}'
        reference = sorted(Path(reference_dir).glob('*.pgm'), key=natural_key)
        assert len(reference) == 100, f'Video decoded to {len(reference)} frames instead of 100'

        for i, (actual_path, reference_path, row) in enumerate(zip(submitted, reference, data_rows)):
            actual = cv2.imread(str(actual_path), cv2.IMREAD_GRAYSCALE)
            expected = cv2.imread(str(reference_path), cv2.IMREAD_GRAYSCALE)
            assert actual is not None, f'Unreadable PGM file: {actual_path}'
            assert expected is not None
            assert actual.shape == expected.shape, f'Wrong dimensions for {actual_path.name}'
            delta = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
            assert int(delta.max()) <= 5 and float(delta.mean()) <= 1.0, \
                f'{actual_path.name} does not match frame {i} of experiment.mp4'

            x, y = int(row[1]), int(row[2])
            height, width = actual.shape
            assert 0 <= x < width and 0 <= y < height, f'Out-of-bounds coordinate in row {i}: {(x, y)}'
            assert int(actual[y, x]) == int(actual.max()), \
                f'Row {i} coordinate {(x, y)} is not a brightest pixel in {actual_path.name}'


def test_extract_tracking_source_compiles_and_handles_unknown_frames():
    assert EXTRACT_SOURCE.is_file(), f'Missing {EXTRACT_SOURCE}'
    binary = Path('/tmp/extract_tracking_verifier')
    compiled = run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(EXTRACT_SOURCE), '-o', str(binary), '-lm'])
    assert compiled.returncode == 0, f'extract_tracking.c does not compile:\n{compiled.stderr}'

    original_names = sorted([p.name for p in FRAMES.glob('*.pgm')], key=natural_key)
    assert len(original_names) == 100
    backup_dir = Path(tempfile.mkdtemp(prefix='frames_backup_'))
    backup_csv = Path('/tmp/extracted_trajectory.backup')
    had_csv = TRAJECTORY.exists()
    if had_csv:
        shutil.copy2(TRAJECTORY, backup_csv)

    expected_points = []
    try:
        for path in FRAMES.glob('*'):
            if path.is_file() or path.is_symlink():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        # Random, unique maxima prevent a hard-coded copy of the known trajectory.
        seed = int.from_bytes(secrets.token_bytes(8), 'big')
        rng = np.random.default_rng(seed)
        for i, name in enumerate(original_names):
            image = rng.integers(0, 90, size=(37, 53), dtype=np.uint8)
            x = int(rng.integers(0, image.shape[1]))
            y = int(rng.integers(0, image.shape[0]))
            image[y, x] = 255
            expected_points.append((x, y))
            write_pgm(FRAMES / name, image)

        execution = run([str(binary)], cwd=str(HOME))
        assert execution.returncode == 0, f'extract_tracking executable failed: {execution.stderr}'
        assert TRAJECTORY.exists(), 'extract_tracking executable did not create extracted_trajectory.csv'
        rows = read_csv(TRAJECTORY)
        assert [c.strip() for c in rows[0]] == ['frame_id', 'x', 'y']
        assert len(rows[1:]) == 100
        observed = [(int(row[1]), int(row[2])) for row in rows[1:]]
        assert observed == expected_points, 'extract_tracking did not derive the brightest pixels from unknown PGM data'
    finally:
        for path in FRAMES.glob('*'):
            if path.is_file() or path.is_symlink():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        for path in backup_dir.iterdir():
            shutil.move(str(path), str(FRAMES / path.name))
        backup_dir.rmdir()
        if had_csv:
            shutil.move(str(backup_csv), str(TRAJECTORY))
        elif TRAJECTORY.exists():
            TRAJECTORY.unlink()


def test_filter_source_pipeline_structure_and_public_corpora():
    assert FILTER_SOURCE.is_file(), f'Missing {FILTER_SOURCE}'
    compiled = run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(FILTER_SOURCE), '-o', '/tmp/artifact_filter_verifier', '-lm'])
    assert compiled.returncode == 0, f'artifact_filter.c does not compile:\n{compiled.stderr}'

    assert PIPELINE.exists(), f'Missing pipeline script at {PIPELINE}'
    assert os.access(PIPELINE, os.X_OK), f'Pipeline script {PIPELINE} is not executable'
    script = PIPELINE.read_text(errors='replace')
    active_script = '\n'.join(line for line in script.splitlines() if not line.lstrip().startswith('#'))
    assert re.search(r'\bartifact_filter\b', active_script), 'pipeline.sh never invokes artifact_filter'

    # Verify that the required 5..30 automated tuning range is represented by a loop.
    has_loop = re.search(r'\b(for|while)\b', active_script) is not None
    has_range = bool(
        re.search(r'\{\s*5\s*\.\.\s*30\s*\}', active_script)
        or re.search(r'\bseq\b[^\n]*\b5\b[^\n]*\b30\b', active_script)
        or re.search(r'for\s*\(\([^\n]*=\s*5[^\n]*(?:<=\s*30|<\s*31)', active_script)
        or all(re.search(rf'(?<!\d){n}(?!\d)', active_script) for n in range(5, 31))
    )
    assert has_loop and has_range, 'pipeline.sh lacks an automated threshold loop covering 5 through 30'

    clean_result = run([str(PIPELINE), '/app/corpora/clean/'])
    assert clean_result.returncode == 0, f'Pipeline failed on clean corpus: {clean_result.stderr}'
    clean_lines = clean_result.stdout.strip().split('\n')
    evil_count = sum(1 for line in clean_lines if 'EVIL' in line)
    clean_count = sum(1 for line in clean_lines if 'CLEAN' in line)
    assert evil_count == 0
    assert clean_count >= 50
    expected_clean = {f'run_{i:02d}.csv' for i in range(1, 51)}
    parsed_clean = classification_map(clean_result.stdout, expected_clean)
    assert parsed_clean == {name: 'CLEAN' for name in expected_clean}

    evil_result = run([str(PIPELINE), '/app/corpora/evil/'])
    assert evil_result.returncode == 0, f'Pipeline failed on evil corpus: {evil_result.stderr}'
    evil_lines = evil_result.stdout.strip().split('\n')
    clean_count = sum(1 for line in evil_lines if 'CLEAN' in line)
    evil_count = sum(1 for line in evil_lines if 'EVIL' in line)
    assert clean_count == 0
    assert evil_count >= 50
    expected_evil = {f'corrupt_{i:02d}.csv' for i in range(1, 51)}
    parsed_evil = classification_map(evil_result.stdout, expected_evil)
    assert parsed_evil == {name: 'EVIL' for name in expected_evil}
    assert FILTER_BINARY.is_file() and os.access(FILTER_BINARY, os.X_OK), \
        'pipeline did not provide a compiled executable artifact_filter'


def test_pipeline_unknown_adversarial_directory_and_filter_invocation():
    with tempfile.TemporaryDirectory(prefix='trajectory_inputs_') as directory:
        directory = Path(directory)
        token = re.sub(r'[^a-z]', '', secrets.token_hex(12)) or 'randomtoken'
        expected = {}

        for i in range(4):
            name = f'{token}smooth{chr(97 + i)}.csv'
            start_x = secrets.randbelow(40) + 80
            start_y = secrets.randbelow(40) + 60
            points = [(start_x + 3*j, start_y + 2*j) for j in range(18)]
            write_csv(directory / name, points)
            expected[name] = 'CLEAN'

        missing_name = f'{token}missing.csv'
        missing = [(100 + 2*j, 90 + j) for j in range(18)]
        missing[7] = (-1, -1)
        write_csv(directory / missing_name, missing)
        expected[missing_name] = 'EVIL'

        for suffix, jump_at in [('jumpalpha', 5), ('jumpbeta', 11), ('jumpgamma', 15)]:
            name = f'{token}{suffix}.csv'
            points = [(120 + 2*j, 70 + j) for j in range(18)]
            x, y = points[jump_at]
            points[jump_at] = (x + 90 + secrets.randbelow(30), y - 80 - secrets.randbelow(30))
            write_csv(directory / name, points)
            expected[name] = 'EVIL'

        # Bash xtrace demonstrates that artifact_filter is actually executed for
        # every arbitrary CSV, rather than classifications being based on a path name.
        result = run(['bash', '-x', str(PIPELINE), str(directory)])
        assert result.returncode == 0, f'Pipeline failed on generated corpus: {result.stderr}'
        parsed = classification_map(result.stdout, set(expected))
        assert parsed == expected, f'Wrong classifications for generated corpus: {parsed}'

        trace_lines = result.stderr.splitlines()
        for name in expected:
            assert any(name in line and re.search(r'\bartifact_filter\b', line) for line in trace_lines), \
                f'pipeline.sh did not invoke artifact_filter on {name}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
