#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

ARCHIVER = "/home/user/archiver"
SOURCE = "/home/user/archiver.c"
ARCHIVE = "/home/user/organized_archive.rle"

EXPECTED_PROJECT_ARCHIVE = (
    "---fileA.txt---\n"
    "A5B5C5\n"
    "---fileB.txt---\n"
    "h1e1l2o3 1w1o1r1l1d3\n"
    "---fileC.txt---\n"
    "l1i1n1e113\n"
    "1l1i1n1e123\n"
    "1\n"
).encode()


def rle(data):
    if not data:
        return b""
    result = bytearray()
    current = data[0]
    count = 1
    for value in data[1:]:
        if value == current:
            count += 1
        else:
            result.append(current)
            result.extend(str(count).encode("ascii"))
            current = value
            count = 1
    result.append(current)
    result.extend(str(count).encode("ascii"))
    return bytes(result)


def expected_for(paths):
    result = bytearray()
    for path in paths:
        result.extend(b"---[" + os.path.basename(path).encode() + b"]---\n")
        result.extend(rle(Path(path).read_bytes()))
        result.extend(b"\n")
    return bytes(result)


def run_archiver(executable, paths):
    stdin_data = "".join(path + "\n" for path in paths).encode()
    completed = subprocess.run(
        [executable],
        input=stdin_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with {completed.returncode}; stderr: "
        f"{completed.stderr.decode(errors='replace')}"
    )
    return completed.stdout


def exercise_with_unseen_files(executable):
    token = secrets.token_hex(8)
    alphabet = "abcXYZ019 !?\t\n"
    random_text = "".join(secrets.choice(alphabet) for _ in range(180)).encode()
    with tempfile.TemporaryDirectory(prefix="archiver_probe_") as directory:
        files = [
            (f"probe_{token}_empty.txt", b""),
            (f"probe_{token}_runs.txt", b"Q" * 17 + b"  " + b"\n\n" + b"z" * 12),
            (f"probe_{token}_random.txt", random_text),
            (f"probe_{token}_tail.txt", b"no trailing newline"),
        ]
        paths = []
        for name, contents in files:
            path = os.path.join(directory, name)
            Path(path).write_bytes(contents)
            paths.append(path)

        # Supply a non-alphabetical order to ensure stdin order is honored.
        paths = [paths[2], paths[0], paths[3], paths[1]]
        actual = run_archiver(executable, paths)
        expected = expected_for(paths)
        assert actual == expected, (
            f"{executable} produced incorrect output for verifier-generated files. "
            f"Expected {expected!r}, got {actual!r}"
        )


def test_archiver_c_exists():
    assert os.path.isfile(SOURCE), "/home/user/archiver.c is missing"


def test_archiver_executable_exists():
    assert os.path.isfile(ARCHIVER), "/home/user/archiver is missing"
    assert os.access(ARCHIVER, os.X_OK), "/home/user/archiver is not executable"


def test_organized_archive_rle():
    assert os.path.isfile(ARCHIVE), f"{ARCHIVE} is missing"
    with open(ARCHIVE, "rb") as f:
        actual_content = f.read()
    assert actual_content == EXPECTED_PROJECT_ARCHIVE, (
        f"Content of {ARCHIVE} does not match expected RLE format. "
        f"Got:\n{actual_content!r}"
    )


def test_submitted_executable_on_unseen_inputs():
    exercise_with_unseen_files(ARCHIVER)


def test_source_compiles_and_implements_archiver():
    with tempfile.TemporaryDirectory(prefix="archiver_build_") as directory:
        compiled = os.path.join(directory, "archiver_from_source")
        build = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE, "-o", compiled],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert build.returncode == 0, (
            "archiver.c did not compile successfully: "
            + build.stderr.decode(errors="replace")
        )
        exercise_with_unseen_files(compiled)


def test_executable_recreates_the_required_archive():
    paths = sorted(
        str(path)
        for path in Path("/home/user/project_files").rglob("*.txt")
        if path.is_file()
    )
    assert paths, "No project .txt files were found"
    regenerated = run_archiver(ARCHIVER, paths)
    assert regenerated == EXPECTED_PROJECT_ARCHIVE, (
        "Running archiver on the recursively found, sorted project files did not "
        "produce the required archive"
    )
    assert regenerated == Path(ARCHIVE).read_bytes(), (
        "organized_archive.rle was not produced by the submitted archiver's output"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
