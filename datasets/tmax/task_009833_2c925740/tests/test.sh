#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import os
import random
import re
import secrets
import stat
import subprocess
import tarfile

HOME = "/home/user"
SOURCE = os.path.join(HOME, "filter_dataset.c")
EXECUTABLE = os.path.join(HOME, "filter_dataset")
CONFIG = os.path.join(HOME, "config.ini")
FILTERED = os.path.join(HOME, "filtered")
ARCHIVE = os.path.join(HOME, "dataset_archive.tar.gz")


def archive_text_files():
    files = {}
    with tarfile.open(ARCHIVE, "r:gz") as outer:
        for outer_member in outer.getmembers():
            if not outer_member.isfile() or not outer_member.name.endswith(".tar"):
                continue
            extracted = outer.extractfile(outer_member)
            assert extracted is not None
            with tarfile.open(fileobj=io.BytesIO(extracted.read()), mode="r:") as inner:
                for member in inner.getmembers():
                    if member.isfile() and member.name.endswith(".txt"):
                        name = os.path.basename(member.name)
                        assert name not in files, f"Duplicate text filename in archives: {name}"
                        stream = inner.extractfile(member)
                        assert stream is not None
                        files[name] = stream.read()
    assert files, "No nested text files were found in dataset_archive.tar.gz."
    return files


def configured_threshold():
    with open(CONFIG, "r", encoding="utf-8") as f:
        text = f.read()
    match = re.fullmatch(r"THRESHOLD=(-?\d+)\n?", text)
    assert match, "config.ini is not in THRESHOLD=X format."
    return int(match.group(1))


def expected_filter(data, threshold):
    values = [int(line) for line in data.decode("utf-8").splitlines()]
    kept = [value for value in values if value > threshold]
    return "".join(f"{value}\n" for value in kept).encode("utf-8")


def run_with_threshold(program, threshold, values):
    original = open(CONFIG, "rb").read()
    try:
        with open(CONFIG, "w", encoding="utf-8") as f:
            f.write(f"THRESHOLD={threshold}\n")
        input_text = "".join(f"{value}\n" for value in values)
        result = subprocess.run(
            [program],
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=HOME,
            timeout=5,
            check=False,
        )
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original)

    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}; stderr: {result.stderr!r}"
    )
    expected = "".join(f"{value}\n" for value in values if value > threshold)
    assert result.stdout == expected, (
        f"{program} produced {result.stdout!r}, expected {expected!r} "
        f"for threshold {threshold} and input {values}"
    )


def exercise_program(program):
    for _ in range(5):
        threshold = secrets.randbelow(20001) - 10000
        values = [
            threshold,
            threshold - 1,
            threshold + 1,
            threshold - secrets.randbelow(5000) - 2,
            threshold + secrets.randbelow(5000) + 2,
            secrets.randbelow(40001) - 20000,
        ]
        random.SystemRandom().shuffle(values)
        run_with_threshold(program, threshold, values)


def test_c_program_exists():
    c_file = "/home/user/filter_dataset.c"
    assert os.path.isfile(c_file), f"C source file {c_file} does not exist."


def test_executable_exists_and_is_executable():
    exe_file = "/home/user/filter_dataset"
    assert os.path.isfile(exe_file), f"Executable {exe_file} does not exist."
    st = os.stat(exe_file)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {exe_file} is not executable."
    with open(exe_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {exe_file} is not a compiled ELF executable."


def test_submitted_executable_filters_arbitrary_input():
    exercise_program(EXECUTABLE)


def test_source_compiles_and_filters_arbitrary_input(tmp_path):
    rebuilt = str(tmp_path / "filter_dataset_rebuilt")
    result = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, f"C source does not compile: {result.stderr}"
    exercise_program(rebuilt)


def test_text_files_were_extracted():
    archived = archive_text_files()
    for filename, expected_data in archived.items():
        matches = []
        for root, dirs, files in os.walk(HOME):
            dirs[:] = [d for d in dirs if os.path.join(root, d) != FILTERED]
            if filename not in files:
                continue
            candidate = os.path.join(root, filename)
            try:
                mode = os.lstat(candidate).st_mode
                if stat.S_ISREG(mode) and open(candidate, "rb").read() == expected_data:
                    matches.append(candidate)
            except OSError:
                pass
        assert matches, f"Extracted source file {filename} was not found outside {FILTERED}."


def test_filtered_files_contents():
    expected_contents = {
        "sensor1.txt": "60\n80\n",
        "sensor2.txt": "51\n100\n",
        "sensor3.txt": "200\n"
    }

    for filename, expected_text in expected_contents.items():
        filepath = os.path.join("/home/user/filtered", filename)
        assert os.path.isfile(filepath), f"Filtered file {filepath} does not exist."

        with open(filepath, "r") as f:
            content = f.read()

        content_lines = [line.strip() for line in content.strip().split('\n') if line.strip()]
        expected_lines = [line.strip() for line in expected_text.strip().split('\n') if line.strip()]

        assert content_lines == expected_lines, f"Content of {filepath} is incorrect. Expected {expected_lines}, got {content_lines}."


def test_filtered_files_match_archive_and_configuration():
    threshold = configured_threshold()
    archived = archive_text_files()
    actual_names = sorted(
        name for name in os.listdir(FILTERED)
        if os.path.isfile(os.path.join(FILTERED, name))
    )
    assert actual_names == sorted(archived), "Filtered directory does not contain exactly the archived text filenames."
    for filename, raw_data in archived.items():
        with open(os.path.join(FILTERED, filename), "rb") as f:
            actual = f.read()
        expected = expected_filter(raw_data, threshold)
        assert actual == expected, f"Filtered output for {filename} is not exact."


def test_manifest_file():
    manifest_path = "/home/user/manifest.txt"
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."

    expected_contents = {
        "sensor1.txt": "60\n80\n",
        "sensor2.txt": "51\n100\n",
        "sensor3.txt": "200\n"
    }

    expected_manifest_lines = []
    for filename in sorted(expected_contents.keys()):
        filepath = os.path.join("/home/user/filtered", filename)
        if os.path.isfile(filepath):
            with open(filepath, "rb") as f:
                file_bytes = f.read()
            file_hash = hashlib.sha256(file_bytes).hexdigest()
            expected_manifest_lines.append(f"{file_hash}  {filename}")

    with open(manifest_path, "r") as f:
        manifest_content = f.read().strip()

    manifest_lines = [line.strip() for line in manifest_content.split('\n') if line.strip()]

    assert len(manifest_lines) == len(expected_manifest_lines), "Manifest does not contain the correct number of entries."

    for expected_line, actual_line in zip(expected_manifest_lines, manifest_lines):
        assert actual_line == expected_line, f"Manifest line mismatch. Expected '{expected_line}', got '{actual_line}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
