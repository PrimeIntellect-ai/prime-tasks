#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import os
import re
import tarfile

import cv2
import numpy as np
import pytest


def test_final_state():
    repository = "/home/user/repository"
    staging = "/home/user/staging"
    index_path = os.path.join(repository, "index.json")

    assert os.path.isdir(staging), f"Staging directory is missing at {staging}"
    assert os.path.exists(index_path), f"Index file is missing at {index_path}"

    with open(index_path, "r") as f:
        try:
            index_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {index_path} is not valid JSON")

    assert isinstance(index_data, dict), "index.json must contain a JSON object"

    predicted_list = []
    for bundle, frames in index_data.items():
        assert isinstance(frames, list), f"Value for {bundle} in index.json must be a list of integers"
        assert all(type(frame) is int for frame in frames), f"Value for {bundle} in index.json must be a list of integers"
        predicted_list.extend(frames)

    assert len(predicted_list) == len(set(predicted_list)), "Frame numbers must not be duplicated in index.json"
    predicted_frames = set(predicted_list)

    expected_bundle_names = [f"bundle_{i}.tar.gz" for i in range(len(index_data))]
    assert set(index_data.keys()) == set(expected_bundle_names), \
        f"Bundles must be named sequentially: {expected_bundle_names}"

    repository_bundles = {
        name for name in os.listdir(repository)
        if re.fullmatch(r"bundle_\d+\.tar\.gz", name)
    }
    assert repository_bundles == set(expected_bundle_names), \
        "Repository bundle files do not match the sequential bundles in index.json"

    for i, bundle in enumerate(expected_bundle_names):
        count = len(index_data[bundle])
        if i < len(expected_bundle_names) - 1:
            assert count == 5, f"{bundle} must contain exactly 5 indexed frames"
        else:
            assert 1 <= count <= 5, f"The last archive {bundle} must contain between 1 and 5 indexed frames"

    video_path = "/app/data_stream.mp4"
    assert os.path.exists(video_path), f"Video file is missing at {video_path}"

    cap = cv2.VideoCapture(video_path)
    true_frames = set()
    decoded_frames = {}
    frame_idx = 1
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        decoded_frames[frame_idx] = gray
        avg_brightness = gray.mean()
        if avg_brightness > 128:
            true_frames.add(frame_idx)
        frame_idx += 1
    cap.release()

    tp = len(true_frames.intersection(predicted_frames))
    fp = len(predicted_frames - true_frames)
    fn = len(true_frames - predicted_frames)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

    assert f1 >= 0.98, f"F1 score {f1:.4f} is below the threshold of 0.98. Precision: {precision:.4f}, Recall: {recall:.4f}"

    for bundle in index_data.keys():
        bundle_path = os.path.join(repository, bundle)
        assert os.path.exists(bundle_path), f"Bundle {bundle_path} listed in index but missing on disk"
        assert os.path.isfile(bundle_path), f"Bundle {bundle_path} must be a regular file"

        try:
            archive = tarfile.open(bundle_path, mode="r:gz")
        except (tarfile.TarError, OSError) as exc:
            pytest.fail(f"Bundle {bundle_path} is not a valid compressed .tar.gz archive: {exc}")

        with archive:
            members = archive.getmembers()
            assert all(member.isfile() or member.isdir() for member in members), \
                f"Bundle {bundle} contains links or unsupported entries"
            frame_members = [member for member in members if member.isfile()]
            indexed = index_data[bundle]
            assert len(frame_members) == len(indexed), \
                f"Bundle {bundle} contains {len(frame_members)} frame files but indexes {len(indexed)} frames"
            assert len({member.name for member in frame_members}) == len(frame_members), \
                f"Bundle {bundle} contains duplicate member names"

            archived_images = []
            for member in frame_members:
                extracted = archive.extractfile(member)
                assert extracted is not None, f"Could not read {member.name} from {bundle}"
                raw = extracted.read()
                image = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_GRAYSCALE)
                assert image is not None, f"Archive member {member.name} in {bundle} is not a decodable image"
                assert image.mean() > 128, f"Archive member {member.name} in {bundle} is not a valid bright frame"
                archived_images.append(image)

            reference_images = []
            for number in indexed:
                assert number in decoded_frames, f"Indexed frame number {number} is outside the video"
                reference_images.append(decoded_frames[number])

            # Archive member order and JSON list order need not be identical, so
            # accept any one-to-one assignment whose decoded pixels match.
            matched = False
            for permutation in itertools.permutations(range(len(reference_images))):
                if all(
                    archived_images[i].shape == reference_images[j].shape
                    and np.mean(np.abs(
                        archived_images[i].astype(np.int16) - reference_images[j].astype(np.int16)
                    )) <= 15.0
                    for i, j in enumerate(permutation)
                ):
                    matched = True
                    break
            assert matched, f"The image files in {bundle} do not match the video frames listed for that bundle"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
