#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

import cv2
import numpy as np


def find_project():
    candidates = [Path.cwd(), Path('/workspace'), Path('/home/user'), Path('/app')]
    for base in candidates:
        if (base / 'inference.sh').is_file():
            return base.resolve()
    raise AssertionError('inference.sh not found in the expected directories')


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def natural_key(path):
    return [int(x) if x.isdigit() else x for x in re.split(r'(\d+)', path.name)]


def test_complete_pipeline_and_inference():
    base = find_project()
    required_scripts = [
        'extract.sh', 'compute_features.sh', 'train.sh', 'inference.sh', 'pipeline.sh'
    ]
    for name in required_scripts:
        path = base / name
        assert path.is_file(), f'{name} is missing'
        assert os.access(path, os.X_OK), f'{name} is not executable'

    # Require pipeline.sh to build all generated artifacts from scratch.
    shutil.rmtree(base / 'data', ignore_errors=True)
    try:
        (base / 'model.pkl').unlink()
    except FileNotFoundError:
        pass
    run_checked([str(base / 'pipeline.sh')], cwd=base, timeout=900)

    frames_dir = base / 'data' / 'frames'
    dataset_path = base / 'data' / 'dataset.csv'
    metrics_path = base / 'data' / 'metrics.log'
    model_path = base / 'model.pkl'

    assert frames_dir.is_dir(), 'pipeline did not create data/frames/'
    frames = sorted(
        [p for p in frames_dir.iterdir() if p.is_file() and p.suffix.lower() in ('.jpg', '.jpeg')],
        key=natural_key,
    )
    assert len(frames) == 300, f'expected all 300 video frames, found {len(frames)}'
    for path in frames:
        image = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
        assert image is not None, f'could not read extracted frame {path}'
        assert image.shape == (128, 128), f'{path} is not a 128x128 grayscale frame'

    assert dataset_path.is_file(), 'data/dataset.csv was not created'
    with dataset_path.open(newline='') as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ['frame_idx', 'sv1', 'sv2', 'sv3', 'sv4', 'sv5'], (
            'dataset.csv has the wrong header'
        )
        rows = list(reader)
    assert len(rows) == len(frames), 'dataset must contain one row per extracted frame'

    by_index = {}
    for row in rows:
        idx = int(row['frame_idx'])
        values = np.array([float(row[f'sv{i}']) for i in range(1, 6)], dtype=float)
        assert np.isfinite(values).all(), f'non-finite singular value at frame {idx}'
        by_index[idx] = values
    assert sorted(by_index) == list(range(1, len(frames) + 1)), (
        'frame_idx must contain each integer from 1 through the number of frames'
    )

    # Independently recompute features for unpredictable rows.
    rng = np.random.default_rng()
    for idx in rng.choice(np.arange(1, len(frames) + 1), size=7, replace=False):
        image = cv2.imread(str(frames[int(idx) - 1]), cv2.IMREAD_GRAYSCALE)
        expected = np.linalg.svd(image.astype(float), compute_uv=False)[:5]
        assert np.allclose(by_index[int(idx)], expected, rtol=1e-3, atol=0.1), (
            f'dataset singular values for frame {idx} do not match the extracted image'
        )

    assert model_path.is_file() and model_path.stat().st_size > 0, 'model.pkl was not created'
    assert metrics_path.is_file() and metrics_path.stat().st_size > 0, 'data/metrics.log was not created'
    metrics = metrics_path.read_text(errors='replace').lower()
    assert 'mae' in metrics, 'metrics.log does not report MAE'
    assert '95' in metrics and ('confidence' in metrics or 'ci' in metrics), (
        'metrics.log does not report a 95% confidence interval'
    )
    assert 'alpha' in metrics, 'metrics.log does not report the tuned alpha'
    assert re.search(r'[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?', metrics), (
        'metrics.log contains no numeric metric values'
    )

    # Check that the training implementation contains the required CV, alpha grid,
    # and bootstrap orchestration, including auxiliary Python files when used.
    training_source = (base / 'train.sh').read_text(errors='replace')
    for py_file in base.glob('*.py'):
        training_source += '\n' + py_file.read_text(errors='replace')
    lower_source = training_source.lower()
    for alpha in ('0.1', '1.0', '10.0'):
        assert alpha in training_source, f'training code does not test alpha={alpha}'
    assert ('ridge' in lower_source), 'training code does not use Ridge regression'
    assert ('bootstrap' in lower_source or 'resample' in lower_source), (
        'training code does not implement bootstrap resampling'
    )
    assert '100' in training_source, 'training code does not perform 100 bootstrap resamples'
    assert re.search(r'(n_splits\s*=\s*5|cv\s*=\s*5|5[- ]?fold)', lower_source), (
        'training code does not specify 5-fold cross-validation'
    )

    # Preserve the original MAE assertion, but use fresh noise, unpredictable names,
    # and randomized invocation order so answers cannot be inferred from filenames.
    inference = base / 'inference.sh'
    indices = np.arange(0, 300, 3)
    rng.shuffle(indices)
    generated = []
    with tempfile.TemporaryDirectory(prefix='hidden_frames_') as test_dir:
        for actual in indices:
            frame = np.zeros((128, 128), dtype=np.uint8)
            center = (int(10 + int(actual) * (108 / 300)),
                      int(64 + 30 * np.sin(int(actual) / 10.0)))
            cv2.circle(frame, center, 15, 255, -1)
            noise = rng.integers(0, 50, (128, 128), dtype=np.uint8)
            frame = cv2.add(frame, noise)
            path = Path(test_dir) / f'{uuid.uuid4().hex}.jpg'
            assert cv2.imwrite(str(path), frame)
            generated.append((path, float(actual)))

        rng.shuffle(generated)
        errors = []
        for image_path, actual in generated:
            result = subprocess.run(
                [str(inference), str(image_path)], cwd=base,
                capture_output=True, text=True, timeout=30
            )
            assert result.returncode == 0, f'inference.sh failed for {image_path}'
            output = result.stdout.strip()
            assert re.fullmatch(
                r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?', output
            ), f'inference.sh must output only one numeric prediction, got {output!r}'
            prediction = float(output)
            assert math.isfinite(prediction), 'inference prediction is not finite'
            errors.append(abs(prediction - actual))

    mae = float(np.mean(errors))
    assert mae <= 20.0, (
        f'Expected MAE <= 20.0, but got {mae:.2f}. '
        'The model predictions are not accurate enough.'
    )
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
