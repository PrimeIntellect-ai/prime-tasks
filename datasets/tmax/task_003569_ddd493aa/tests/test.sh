#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import shutil
import subprocess
import uuid


def test_detect_go_exists():
    path = "/home/user/detect.go"
    assert os.path.isfile(path), f"The Go program {path} was not created."


def test_found_archives_txt_exists():
    path = "/home/user/found_archives.txt"
    assert os.path.isfile(path), f"The output file {path} was not created."


def test_found_archives_content():
    path = "/home/user/found_archives.txt"
    assert os.path.isfile(path), f"The output file {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "/home/user/project_files/hidden_gzip.dat",
        "/home/user/project_files/no_extension_file",
        "/home/user/project_files/subdir/fake_document.pdf"
    ]

    assert lines == expected, (
        f"The contents of {path} do not match the expected sorted list of archives.\n"
        f"Expected: {expected}\n"
        f"Got: {lines}"
    )


def detected_archives():
    expected = []
    root = "/home/user/project_files"
    for directory, _, filenames in os.walk(root):
        for filename in filenames:
            path = os.path.abspath(os.path.join(directory, filename))
            try:
                with open(path, "rb") as f:
                    header = f.read(4)
            except OSError:
                continue
            if header.startswith(bytes.fromhex("50 4b 03 04")) or header.startswith(bytes.fromhex("1f 8b 08")):
                expected.append(path)
    return expected


def run_detector(executable):
    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"The compiled detector exited with status {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def test_program_compiles_and_dynamically_detects_headers():
    token = uuid.uuid4().hex
    executable = f"/tmp/detect_{token}"
    test_root = os.path.join("/home/user/project_files", f"dynamic_{token}")
    deep_root = os.path.join(test_root, "nested", "deeper")
    os.makedirs(deep_root)

    zip_path = os.path.join(deep_root, f"ordinary_{token}.txt")
    gzip_path = os.path.join(test_root, f"no_extension_{token}")
    decoy_path = os.path.join(deep_root, f"decoy_{token}.zip")
    near_zip_path = os.path.join(test_root, f"near_zip_{token}.bin")
    near_gzip_path = os.path.join(test_root, f"near_gzip_{token}.bin")

    with open(zip_path, "wb") as f:
        f.write(bytes.fromhex("50 4b 03 04") + b"dynamic zip payload")
    with open(gzip_path, "wb") as f:
        f.write(bytes.fromhex("1f 8b 08") + b"dynamic gzip payload")
    with open(decoy_path, "wb") as f:
        f.write(b"not an archive despite its extension")
    with open(near_zip_path, "wb") as f:
        f.write(bytes.fromhex("50 4b 03 05") + b"near miss")
    with open(near_gzip_path, "wb") as f:
        f.write(bytes.fromhex("1f 8b 07") + b"near miss")

    try:
        build = subprocess.run(
            ["go", "build", "-o", executable, "/home/user/detect.go"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, (
            f"/home/user/detect.go did not compile.\nstdout:\n{build.stdout}\n"
            f"stderr:\n{build.stderr}"
        )
        assert os.path.isfile(executable), "Go build did not produce an executable."

        expected_first = detected_archives()
        actual_first = run_detector(executable)
        assert collections.Counter(actual_first) == collections.Counter(expected_first), (
            "The detector's output did not match files identified by their current binary headers.\n"
            f"Expected: {sorted(expected_first)}\nGot: {sorted(actual_first)}"
        )

        # Change signatures after the first run to ensure results are computed dynamically.
        with open(zip_path, "wb") as f:
            f.write(b"the archive signature was removed")
        with open(decoy_path, "wb") as f:
            f.write(bytes.fromhex("1f 8b 08") + b"newly disguised gzip payload")

        expected_second = detected_archives()
        actual_second = run_detector(executable)
        assert collections.Counter(actual_second) == collections.Counter(expected_second), (
            "The detector did not respond correctly when file headers changed.\n"
            f"Expected: {sorted(expected_second)}\nGot: {sorted(actual_second)}"
        )
    finally:
        shutil.rmtree(test_root, ignore_errors=True)
        try:
            os.remove(executable)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
