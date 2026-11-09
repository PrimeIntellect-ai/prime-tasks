#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import random
import shutil
import subprocess
import time

import pytest


def golden_files_and_paths():
    random.seed(42)
    expected = {}
    archive_paths = []

    for i in range(2500):
        basename = f"file_{i}.txt"
        if random.random() < 0.2:
            path = f"../../etc/fake_{i}/" + basename
        elif random.random() < 0.4:
            path = f"nested/../../../home/user/fake_{i}/" + basename
        else:
            path = "normal_dir/" + basename

        byte = bytes([random.randint(65, 90)])
        length = random.randint(100, 50000)
        expected[basename] = hashlib.md5(byte * length).hexdigest()
        archive_paths.append(path)

    return expected, archive_paths


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_fast_extractor_exists_and_executable():
    executable = "/home/user/fast_extractor"
    assert os.path.exists(executable), f"Executable {executable} not found."
    assert os.path.isfile(executable), f"{executable} is not a file."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."

    source = "/home/user/fast_extractor.cpp"
    assert os.path.isfile(source), f"Source file {source} not found."


def test_zip_slip_prevention():
    # Retain the original explicit zip-slip assertions.
    assert not os.path.exists("/home/user/etc/shadow"), "Zip-slip vulnerability detected! File leaked to /home/user/etc/shadow"
    assert not os.path.exists("/etc/shadow_leaked"), "Zip-slip vulnerability detected! File leaked to /etc/shadow_leaked"
    assert not os.path.exists("/home/user/.bashrc_leaked"), "Zip-slip vulnerability detected!"


def test_accuracy_and_performance():
    executable = "/home/user/fast_extractor"
    dataset_dir = "/home/user/dataset"
    output_dir = "/home/user/output"
    run_cwd = "/home/user"

    expected, stored_paths = golden_files_and_paths()

    archives = glob.glob(os.path.join(dataset_dir, "*.parc"))
    assert len(archives) == 1000, f"Expected 1000 input archives, found {len(archives)}."

    # Clean output completely so only this verifier invocation is assessed.
    os.makedirs(output_dir, exist_ok=True)
    for entry in os.scandir(output_dir):
        remove_path(entry.path)

    # Remove the exact locations to which the generated archive names would escape
    # if interpreted relative to the controlled working directory.
    leaked_targets = set()
    leaked_parents = set()
    for stored_path in stored_paths:
        target = os.path.realpath(os.path.join(run_cwd, stored_path))
        leaked_targets.add(target)
        leaked_parents.add(os.path.dirname(target))

    for parent in sorted(leaked_parents, key=len, reverse=True):
        if parent != output_dir and os.path.lexists(parent):
            remove_path(parent)

    start_time = time.time()
    try:
        subprocess.run(
            [executable, dataset_dir, output_dir],
            check=True,
            capture_output=True,
            text=True,
            cwd=run_cwd,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Extractor failed to run: {e.stderr}")
    elapsed = time.time() - start_time

    extracted_files = len(os.listdir(output_dir))
    assert extracted_files > 0, "No files were extracted to the output directory."

    # Retain the original flattening assertion.
    for root, dirs, files in os.walk(output_dir):
        assert root == output_dir or len(files) == 0, "Directories found in output, structure was not flattened."

    actual_names = set(os.listdir(output_dir))
    expected_names = set(expected)
    assert actual_names == expected_names, (
        f"Extracted file set mismatch: missing={sorted(expected_names - actual_names)[:10]}, "
        f"unexpected={sorted(actual_names - expected_names)[:10]}"
    )

    for basename, expected_md5 in expected.items():
        path = os.path.join(output_dir, basename)
        assert os.path.isfile(path) and not os.path.islink(path), f"{path} is not a regular extracted file."
        digest = hashlib.md5()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                digest.update(chunk)
        assert digest.hexdigest() == expected_md5, f"Incorrect contents for {basename}."

    escaped = [path for path in leaked_targets if os.path.lexists(path)]
    assert not escaped, f"Zip-slip vulnerability detected; escaped files include: {escaped[:10]}"

    # Repeat the original named checks after execution as well.
    assert not os.path.exists("/home/user/etc/shadow"), "Zip-slip vulnerability detected! File leaked to /home/user/etc/shadow"
    assert not os.path.exists("/etc/shadow_leaked"), "Zip-slip vulnerability detected! File leaked to /etc/shadow_leaked"
    assert not os.path.exists("/home/user/.bashrc_leaked"), "Zip-slip vulnerability detected!"

    threshold = 1.5
    assert elapsed <= threshold, f"Performance metric failed: runtime {elapsed:.4f}s > threshold {threshold}s"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
