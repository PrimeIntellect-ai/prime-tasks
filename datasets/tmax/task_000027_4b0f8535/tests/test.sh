#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import struct
import subprocess
import tempfile

AGENT_SOURCE = "/home/user/safe_unpacker.c"
AGENT_EXECUTABLE = "/home/user/safe_unpacker"


def write_archive(path, records):
    with open(path, "wb") as f:
        f.write(b"CARC")
        for name, content in records:
            encoded = name.encode("utf-16le")
            assert len(encoded) <= 0xffff
            f.write(struct.pack("<H", len(encoded)))
            f.write(encoded)
            f.write(struct.pack("<I", len(content)))
            f.write(content)


def get_dir_state(directory):
    state = {}
    for root, _, files in os.walk(directory):
        for filename in files:
            path = os.path.join(root, filename)
            rel = os.path.relpath(path, directory)
            with open(path, "rb") as f:
                state[rel] = f.read()
    return state


def test_agent_artifacts_exist_and_are_c_program():
    assert os.path.isfile(AGENT_SOURCE), f"C source not found at {AGENT_SOURCE}"
    assert os.path.isfile(AGENT_EXECUTABLE), f"Agent executable not found at {AGENT_EXECUTABLE}"
    assert os.access(AGENT_EXECUTABLE, os.X_OK), f"Agent executable is not executable: {AGENT_EXECUTABLE}"

    with open(AGENT_EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "safe_unpacker must be a compiled executable"

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "safe_unpacker")
        result = subprocess.run(
            ["gcc", AGENT_SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"safe_unpacker.c does not compile:\n{result.stderr}"


def test_requires_exactly_two_arguments():
    no_args = subprocess.run([AGENT_EXECUTABLE], capture_output=True, timeout=5)
    extra_args = subprocess.run(
        [AGENT_EXECUTABLE, "a", "b", "c"], capture_output=True, timeout=5
    )
    assert no_args.returncode != 0
    assert extra_args.returncode != 0


def test_format_extraction_encoding_and_path_security():
    global_absolute_paths = []
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            for seed in range(1000):
                rng = random.Random(seed)
                case_dir = os.path.join(tmpdir, f"case_{seed}")
                target_dir = os.path.join(case_dir, "target")
                os.makedirs(target_dir)

                records = []
                expected = {}
                expected_warnings = []
                outside_paths = []

                num_files = rng.randint(0, 15)
                for index in range(num_files):
                    path_type = rng.choice([
                        "normal",
                        "unicode",
                        "top_level",
                        "traversal_unix",
                        "traversal_win",
                        "absolute_unix",
                        "absolute_win",
                        "mixed_escape",
                    ])

                    if path_type == "normal":
                        name = f"dir{rng.randint(1, 5)}/sub/file_{seed}_{index}.bin"
                    elif path_type == "unicode":
                        name = f"configs_{seed}/café_配置_😀_{index}.bin"
                    elif path_type == "top_level":
                        name = f"config_{seed}_{index}.bin"
                    elif path_type == "traversal_unix":
                        name = f"../../escaped_{seed}_{index}.bin"
                        outside_paths.append(os.path.normpath(os.path.join(target_dir, name)))
                    elif path_type == "traversal_win":
                        name = f"..\\..\\escaped_{seed}_{index}.bin"
                    elif path_type == "absolute_unix":
                        name = f"/tmp/safe_unpacker_verify_{os.getpid()}_{seed}_{index}"
                        global_absolute_paths.append(name)
                        outside_paths.append(name)
                    elif path_type == "absolute_win":
                        name = f"C:\\Windows\\System32\\config_{seed}_{index}.bin"
                    else:
                        name = f"safe/../../escaped_{seed}_{index}.bin"
                        outside_paths.append(os.path.normpath(os.path.join(target_dir, name)))

                    content = rng.randbytes(rng.randint(0, 512))
                    records.append((name, content))

                    if path_type in ("normal", "unicode", "top_level"):
                        expected[os.path.normpath(name)] = content
                    else:
                        expected_warnings.append(f"WARNING: Skipped malicious path {name}")

                archive_path = os.path.join(case_dir, "archive.bin")
                write_archive(archive_path, records)

                result = subprocess.run(
                    [AGENT_EXECUTABLE, archive_path, target_dir],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                assert result.returncode == 0, (
                    f"Unpacker failed on seed {seed} with code {result.returncode}:\n"
                    f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
                )

                actual = get_dir_state(target_dir)
                assert actual == expected, (
                    f"Extraction mismatch on seed {seed}.\n"
                    f"Expected files: {list(expected.keys())}\n"
                    f"Actual files: {list(actual.keys())}\n"
                    f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
                )

                output_lines = result.stdout.splitlines()
                for warning in expected_warnings:
                    assert warning in output_lines, (
                        f"Missing required warning on seed {seed}: {warning!r}\n"
                        f"stdout:\n{result.stdout}"
                    )

                for outside_path in outside_paths:
                    assert not os.path.exists(outside_path), (
                        f"Malicious archive path escaped the target directory: {outside_path}"
                    )
    finally:
        for path in global_absolute_paths:
            try:
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    test_agent_artifacts_exist_and_are_c_program()
    test_requires_exactly_two_arguments()
    test_format_extraction_encoding_and_path_security()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
