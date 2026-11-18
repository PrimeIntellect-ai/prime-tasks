#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import subprocess
import tempfile
import uuid


def compute_checksum(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    return sum(data) % 256


def get_expected_manifest_lines(target_dir):
    lines = []
    for root, dirs, files in os.walk(target_dir):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for name in files:
            filepath = os.path.join(root, name)
            if not os.path.islink(filepath) and os.path.isfile(filepath):
                size = os.path.getsize(filepath)
                checksum = compute_checksum(filepath)
                lines.append(f"{filepath} {size} {checksum}")
    lines.sort()
    return lines


def run_tracker():
    subprocess.run(
        ["/tmp/tracker_verifier"],
        cwd="/home/user",
        check=True,
        timeout=10,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_tracker_cpp_exists():
    assert os.path.isfile("/home/user/tracker.cpp"), "/home/user/tracker.cpp is missing. Did you write the C++ program?"


def test_tracker_compiles_and_runs():
    manifest = pathlib.Path("/home/user/manifest.txt")
    if manifest.exists() or manifest.is_symlink():
        manifest.unlink()

    subprocess.run(
        ["g++", "-std=c++17", "/home/user/tracker.cpp", "-o", "/tmp/tracker_verifier"],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    run_tracker()


def test_manifest_exists():
    assert os.path.isfile("/home/user/manifest.txt"), "/home/user/manifest.txt is missing. Did the program run successfully?"


def test_manifest_contents():
    target_dir = "/home/user/config_data"
    manifest_path = "/home/user/manifest.txt"

    assert os.path.isdir(target_dir), f"Target directory {target_dir} is missing."
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} is missing."

    expected_lines = get_expected_manifest_lines(target_dir)

    with open(manifest_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Manifest contents do not match expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_tracker_uses_config_and_handles_dynamic_tree():
    config_path = pathlib.Path("/home/user/backup.conf")
    original_config = config_path.read_bytes()

    with tempfile.TemporaryDirectory(prefix="tracker_test_") as temp_root:
        root = pathlib.Path(temp_root)
        target = root / ("target_" + uuid.uuid4().hex)
        output = root / ("manifest_" + uuid.uuid4().hex + ".txt")
        nested = target / ("nested_" + uuid.uuid4().hex)
        nested.mkdir(parents=True)

        files = {
            target / ("alpha_" + uuid.uuid4().hex + ".bin"): os.urandom(37),
            nested / ("beta_" + uuid.uuid4().hex + ".dat"): bytes(range(256)) + os.urandom(19),
            nested / ("empty_" + uuid.uuid4().hex): b"",
        }
        for path, data in files.items():
            path.write_bytes(data)

        outside = root / ("outside_" + uuid.uuid4().hex)
        outside.write_bytes(os.urandom(23))
        os.symlink(outside, target / "linked_file")
        os.symlink(target, nested / "loop")
        os.symlink(root, target / "linked_directory")

        expected_lines = sorted(
            f"{path} {len(data)} {sum(data) % 256}" for path, data in files.items()
        )

        try:
            config_path.write_text(f"TARGET={target}\nOUTPUT={output}\n")
            run_tracker()

            assert output.is_file(), "Tracker did not write to the OUTPUT path from backup.conf"
            actual_lines = output.read_text().splitlines()
            assert actual_lines == expected_lines, (
                f"Dynamic manifest contents do not match expected output.\n"
                f"Expected: {expected_lines}\n"
                f"Actual: {actual_lines}"
            )
        finally:
            config_path.write_bytes(original_config)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
