#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import shutil
import subprocess
import tempfile
import time
import uuid

import numpy as np
import pytest
from PIL import Image


def compute_reference(video_path='/app/experiment_feed.mp4'):
    with tempfile.TemporaryDirectory(prefix='ref_frames_') as ref_dir:
        subprocess.run([
            'ffmpeg', '-y', '-i', video_path,
            '-vf', 'fps=4,scale=128:128,format=gray',
            os.path.join(ref_dir, 'frame_%04d.png')
        ], check=True, capture_output=True)

        frames = []
        for file in sorted(os.listdir(ref_dir)):
            if file.endswith('.png'):
                with Image.open(os.path.join(ref_dir, file)) as img:
                    frames.append(np.array(img))
        return np.array(frames)


def test_dataset_npz_and_metric():
    dataset_path = '/home/user/dataset.npz'
    assert os.path.exists(dataset_path), f"File {dataset_path} does not exist."

    try:
        data = np.load(dataset_path)
        agent_frames = data['frames']
    except Exception as e:
        pytest.fail(f"Could not load 'frames' from {dataset_path}: {e}")

    assert agent_frames.dtype == np.uint8, f"Expected dtype uint8, got {agent_frames.dtype}"

    ref_frames = compute_reference()
    assert agent_frames.shape == ref_frames.shape, f"Shape mismatch: expected {ref_frames.shape}, got {agent_frames.shape}"

    mse = np.mean((agent_frames.astype(np.float32) - ref_frames.astype(np.float32)) ** 2)
    assert mse <= 2.0, f"MSE {mse} is greater than the threshold 2.0"


def test_chunks():
    dataset_path = '/home/user/dataset.npz'
    assert os.path.exists(dataset_path)
    agent_frames = np.load(dataset_path)['frames']

    chunks_dir = '/home/user/chunks'
    assert os.path.exists(chunks_dir) and os.path.isdir(chunks_dir), f"Directory {chunks_dir} does not exist."

    num_frames = len(agent_frames)
    expected_num_chunks = (num_frames + 49) // 50

    chunk_files = sorted([f for f in os.listdir(chunks_dir) if f.endswith('.npz')])
    assert len(chunk_files) == expected_num_chunks, f"Expected {expected_num_chunks} chunks, got {len(chunk_files)}"

    for i in range(expected_num_chunks):
        expected_filename = f"chunk_{i:03d}.npz"
        assert expected_filename in chunk_files, f"Expected chunk file {expected_filename} not found."

        chunk_path = os.path.join(chunks_dir, expected_filename)
        try:
            chunk_data = np.load(chunk_path)['frames']
        except Exception as e:
            pytest.fail(f"Could not load 'frames' from {chunk_path}: {e}")

        start_idx = i * 50
        end_idx = min((i + 1) * 50, num_frames)
        expected_chunk = agent_frames[start_idx:end_idx]

        assert np.array_equal(chunk_data, expected_chunk), f"Data mismatch in {expected_filename}"


def test_watcher_script():
    watcher_path = '/home/user/watcher.py'
    assert os.path.exists(watcher_path), f"File {watcher_path} does not exist."

    with open(watcher_path, 'r') as f:
        content = f.read()

    assert 'watchdog' in content, "The watcher script does not seem to use the 'watchdog' library."
    assert '/home/user/incoming' in content or '/home/user/incoming/' in content, "The watcher script does not contain the incoming directory path."
    assert '/home/user/processed' in content or '/home/user/processed/' in content, "The watcher script does not contain the processed directory path."

    incoming_dir = '/home/user/incoming'
    processed_dir = '/home/user/processed'
    os.makedirs(incoming_dir, exist_ok=True)
    os.makedirs(processed_dir, exist_ok=True)

    probe_id = 'watcher_probe_' + uuid.uuid4().hex
    source_video = os.path.join('/tmp', probe_id + '.mp4')
    incoming_video = os.path.join(incoming_dir, probe_id + '.mp4')
    output_archive = os.path.join(processed_dir, probe_id + '.npz')

    subprocess.run([
        'ffmpeg', '-y', '-f', 'lavfi',
        '-i', 'testsrc2=duration=3:size=196x142:rate=20',
        '-pix_fmt', 'yuv420p', source_video
    ], check=True, capture_output=True)
    expected_frames = compute_reference(source_video)

    proc = subprocess.Popen(
        ['python3', watcher_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

    try:
        time.sleep(1.5)
        assert proc.poll() is None, "The watcher script exited before it could monitor the incoming directory."

        # A hard link makes a complete MP4 appear atomically while still producing
        # a watchdog creation event in the monitored directory.
        os.link(source_video, incoming_video)

        deadline = time.time() + 30
        watcher_frames = None
        last_error = None
        while time.time() < deadline:
            if os.path.exists(output_archive):
                try:
                    with np.load(output_archive) as result:
                        assert result.files == ['frames'], \
                            f"Watcher output must contain only 'frames', got {result.files}"
                        watcher_frames = result['frames'].copy()
                    break
                except (OSError, ValueError, EOFError) as e:
                    last_error = e
            if proc.poll() is not None:
                break
            time.sleep(0.25)

        assert watcher_frames is not None, \
            f"Watcher did not create a readable {output_archive}: {last_error}"
        assert watcher_frames.dtype == np.uint8, \
            f"Expected watcher output dtype uint8, got {watcher_frames.dtype}"
        assert watcher_frames.shape == expected_frames.shape, \
            f"Watcher shape mismatch: expected {expected_frames.shape}, got {watcher_frames.shape}"

        mse = np.mean((watcher_frames.astype(np.float32) - expected_frames.astype(np.float32)) ** 2)
        assert mse <= 2.0, f"Watcher output MSE {mse} is greater than the threshold 2.0"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
        for path in (incoming_video, output_archive, source_video):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
