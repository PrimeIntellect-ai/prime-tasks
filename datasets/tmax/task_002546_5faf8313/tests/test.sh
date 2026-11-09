#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import subprocess
import pytest

PROJECT_DIR = "/home/user/dataset_organizer"
DATA_PATH = "/home/user/data.csv"
JSON_PATH = "/home/user/best_model.json"
SCRIPT_PATH = "/home/user/run_pipeline.sh"


def get_vec(text):
    t = text.lower()
    bigrams = ["th", "he", "in", "er", "an"]
    vec = []
    for bg in bigrams:
        count = 0
        for i in range(len(t) - 1):
            if t[i:i + 2] == bg:
                count += 1
        vec.append(count)
    return vec


def dist(v1, v2):
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(v1, v2)))


def compute_expected(data_path=DATA_PATH):
    dataset = []
    with open(data_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            dataset.append((get_vec(row["text"]), row["label"]))

    accuracies = {}
    for k in [1, 2, 3]:
        correct = 0
        for i in range(len(dataset)):
            test_vec, test_label = dataset[i]

            dists = []
            for j in range(len(dataset)):
                if i == j:
                    continue
                train_vec, train_label = dataset[j]
                dists.append((dist(test_vec, train_vec), train_label))

            dists.sort(key=lambda x: x[0])
            neighbors = dists[:k]

            counts = {}
            for _, label in neighbors:
                counts[label] = counts.get(label, 0) + 1

            sorted_counts = sorted(counts.items(), key=lambda x: (-x[1], x[0]))
            pred = sorted_counts[0][0]
            if pred == test_label:
                correct += 1

        accuracies[k] = correct / len(dataset)

    best_k = 1
    best_acc = -1
    for k in [1, 2, 3]:
        if accuracies[k] > best_acc:
            best_acc = accuracies[k]
            best_k = k

    return best_k, best_acc


def read_and_check_output(expected_k, expected_acc):
    assert os.path.isfile(JSON_PATH), f"Output JSON file missing at {JSON_PATH}"
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")

    assert "best_k" in data, f"'best_k' missing in {JSON_PATH}"
    assert "accuracy" in data, f"'accuracy' missing in {JSON_PATH}"
    assert data["best_k"] == expected_k, f"Expected best_k to be {expected_k}, got {data['best_k']}"
    assert abs(data["accuracy"] - expected_acc) < 1e-5, \
        f"Expected accuracy to be {expected_acc}, got {data['accuracy']}"


def build_rust_binary():
    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    target_dir = "/tmp/verifier-rust-target"
    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
        cwd=PROJECT_DIR, capture_output=True, text=True
    )
    assert metadata_result.returncode == 0, \
        f"cargo metadata failed.\nStdout: {metadata_result.stdout}\nStderr: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    manifest_real = os.path.realpath(manifest)
    packages = [p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == manifest_real]
    assert packages, "Could not identify the submitted Rust package"
    package = packages[0]
    bin_targets = [t for t in package["targets"] if "bin" in t["kind"]]
    assert bin_targets, "The submitted Cargo project has no binary target"

    default_run = package.get("default_run")
    target = next((t for t in bin_targets if t["name"] == default_run), bin_targets[0])
    build_result = subprocess.run(
        ["cargo", "build", "--release", "--target-dir", target_dir,
         "--manifest-path", manifest, "--bin", target["name"]],
        cwd=PROJECT_DIR, capture_output=True, text=True
    )
    assert build_result.returncode == 0, \
        f"Release build failed.\nStdout: {build_result.stdout}\nStderr: {build_result.stderr}"
    binary = os.path.join(target_dir, "release", target["name"])
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), \
        f"Built Rust binary is missing or not executable: {binary}"
    return binary


def run_binary(binary):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = subprocess.run([binary], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert result.returncode == 0, \
        f"Built Rust binary failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def encode_vector(vec, uppercase=False):
    bigrams = ["th", "he", "in", "er", "an"]
    parts = []
    for bg, count in zip(bigrams, vec):
        parts.extend([bg] * count)
    text = "|".join(parts) if parts else "xyz"
    return text.upper() if uppercase else text


def write_dataset(rows):
    with open(DATA_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["text", "label"])
        writer.writerows(rows)


def assert_no_distance_ties(rows):
    vectors = [get_vec(text) for text, _ in rows]
    for i, vector in enumerate(vectors):
        squared = []
        for j, other in enumerate(vectors):
            if i != j:
                squared.append(sum((a - b) ** 2 for a, b in zip(vector, other)))
        assert len(squared) == len(set(squared)), "Verifier fixture unexpectedly has distance ties"


def test_rust_project_setup():
    assert os.path.isdir(PROJECT_DIR), f"Rust project directory missing at {PROJECT_DIR}"
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml missing at {cargo_toml}"
    main_rs = os.path.join(PROJECT_DIR, "src", "main.rs")
    assert os.path.isfile(main_rs), f"src/main.rs missing at {main_rs}"


def test_run_pipeline_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, \
        f"Pipeline script failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"


def test_best_model_output():
    expected_k, expected_acc = compute_expected()
    read_and_check_output(expected_k, expected_acc)


def test_built_rust_program_on_additional_inputs():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    binary = build_rust_binary()
    positions = [0, 1, 4, 10, 12, 17]
    label_patterns = [
        ["B", "A", "B", "A", "A", "B"],
        ["A", "C", "B", "C", "A", "B"],
        ["C", "C", "A", "B", "A", "B"],
        ["B", "A", "A", "C", "B", "C"],
        ["C", "A", "B", "B", "C", "A"],
    ]

    cases = []
    for dimension in range(5):
        rows = []
        for index, position in enumerate(positions):
            vector = [0, 0, 0, 0, 0]
            vector[dimension] = position
            rows.append((encode_vector(vector, uppercase=(index % 2 == 1)),
                         label_patterns[dimension][index]))
        cases.append(rows)

    mixed_vectors = [
        [0, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [0, 2, 0, 0, 0],
        [0, 0, 3, 0, 0],
        [0, 0, 0, 5, 0],
        [0, 0, 0, 0, 8],
        [1, 2, 3, 5, 8],
    ]
    mixed_labels = ["Z", "A", "Z", "M", "A", "M", "Z"]
    cases.append([
        (encode_vector(vector, uppercase=(i % 2 == 0)), mixed_labels[i])
        for i, vector in enumerate(mixed_vectors)
    ])

    try:
        for rows in cases:
            assert_no_distance_ties(rows)
            write_dataset(rows)
            expected_k, expected_acc = compute_expected()
            run_binary(binary)
            read_and_check_output(expected_k, expected_acc)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
