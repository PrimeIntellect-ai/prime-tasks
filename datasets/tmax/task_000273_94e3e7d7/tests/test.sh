#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import time

import librosa
import numpy as np
import pandas as pd
import pytest
import requests
from sklearn.decomposition import PCA

BASE_URL = "http://127.0.0.1:8000"


def expected_records():
    primary = pd.read_csv("/home/user/data/primary.csv")
    secondary = pd.read_csv("/home/user/data/secondary.csv")
    joined = primary.merge(secondary, on="id", how="left")
    joined["id"] = joined["id"].astype("Int64")

    y, sr = librosa.load("/app/audio/sample.wav", sr=None)
    mfcc_means = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13).mean(axis=1)
    features = np.column_stack([
        joined["feature_val"].to_numpy(dtype=float),
        np.tile(mfcc_means, (len(joined), 1)),
    ])
    reduced = PCA(n_components=2).fit_transform(features)

    return {
        int(row.id): {
            "id": int(row.id),
            "token_count": len(str(row.text_description).split()),
            "pca_1": float(reduced[i, 0]),
            "pca_2": float(reduced[i, 1]),
        }
        for i, row in joined.reset_index(drop=True).iterrows()
    }


EXPECTED = expected_records()


def assert_record(record_id):
    response = requests.get(f"{BASE_URL}/record?id={record_id}", timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    data = response.json()

    assert "id" in data, "Response missing 'id' field"
    assert "token_count" in data, "Response missing 'token_count' field"
    assert "pca_1" in data, "Response missing 'pca_1' field"
    assert "pca_2" in data, "Response missing 'pca_2' field"

    expected = EXPECTED[record_id]
    assert type(data["id"]) is int, f"Expected 'id' to be int, got {type(data['id'])}"
    assert data["id"] == expected["id"]
    assert type(data["token_count"]) is int
    assert data["token_count"] == expected["token_count"]
    assert isinstance(data["pca_1"], float), f"Expected 'pca_1' to be float, got {type(data['pca_1'])}"
    assert isinstance(data["pca_2"], float), f"Expected 'pca_2' to be float, got {type(data['pca_2'])}"
    assert math.isfinite(data["pca_1"])
    assert math.isfinite(data["pca_2"])
    assert data["pca_1"] == pytest.approx(expected["pca_1"], rel=1e-6, abs=1e-7)
    assert data["pca_2"] == pytest.approx(expected["pca_2"], rel=1e-6, abs=1e-7)


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == 8000 and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith("socket:[") and target[8:-1] in inodes:
            pids.add(int(fd.split("/")[2]))
    return pids


def cpu_ticks(pids):
    total = 0
    for pid in pids:
        try:
            with open(f"/proc/{pid}/stat") as f:
                fields = f.read().split()
            total += int(fields[13]) + int(fields[14])
        except (FileNotFoundError, ProcessLookupError):
            pass
    return total


def test_record_endpoint_id_1():
    assert_record(1)
    assert EXPECTED[1]["token_count"] == 5


def test_record_endpoint_id_2():
    assert_record(2)
    assert EXPECTED[2]["token_count"] == 6


def test_record_endpoint_id_3():
    assert_record(3)
    assert EXPECTED[3]["token_count"] == 2


def test_benchmark_endpoint():
    pids = listener_pids()
    assert pids, "Could not identify the process listening on 127.0.0.1:8000"
    before = cpu_ticks(pids)

    results = []
    for _ in range(3):
        started = time.perf_counter()
        response = requests.get(f"{BASE_URL}/benchmark", timeout=30)
        elapsed_ms = (time.perf_counter() - started) * 1000.0
        assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
        data = response.json()
        assert "avg_inference_time_ms" in data, "Response missing 'avg_inference_time_ms' field"
        value = data["avg_inference_time_ms"]
        assert isinstance(value, float), f"Expected float, got {type(value)}"
        assert math.isfinite(value)
        assert value > 0, "Average inference time should be greater than 0"
        # The reported total transform time cannot exceed the complete request by a large margin.
        assert value * 1000.0 <= elapsed_ms + 50.0
        results.append(value)

    after = cpu_ticks(pids)
    # Three calls require 3000 sequential sklearn transform invocations. Requiring
    # measurable server CPU rejects a static endpoint that only returns a number.
    assert after - before >= 2, "Benchmark endpoint performed no measurable transform workload"

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
