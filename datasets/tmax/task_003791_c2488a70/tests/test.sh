#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tarfile
import tempfile


def test_final_docs_archive_exists_and_valid():
    archive_path = "/home/user/final_docs.tar.gz"
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar file."


def test_final_docs_content():
    archive_path = "/home/user/final_docs.tar.gz"
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(archive_path, "r:gz") as tar:
            tar.extractall(tmpdir)

        # Find the files, which may be nested.
        found_files = {}
        for root, dirs, files in os.walk(tmpdir):
            for file in files:
                if file in ["readme.txt", "arch.md", "notes.txt"]:
                    found_files[file] = os.path.join(root, file)

        assert "readme.txt" in found_files, "readme.txt not found in final_docs.tar.gz"
        assert "arch.md" in found_files, "arch.md not found in final_docs.tar.gz"
        assert "notes.txt" in found_files, "notes.txt not found in final_docs.tar.gz"

        with open(found_files["readme.txt"], "r") as f:
            content = f.read().strip()
            expected = "Welcome to NovaTech.&4&This is v2.2 of our software."
            assert content == expected, f"readme.txt content is incorrect. Expected: '{expected}', Got: '{content}'"

        with open(found_files["arch.md"], "r") as f:
            content = f.read().strip()
            expected = "NovaTech v2.2 architecture:  Client ->   Server."
            assert content == expected, f"arch.md content is incorrect. Expected: '{expected}', Got: '{content}'"

        with open(found_files["notes.txt"], "r") as f:
            content = f.read().strip()
            expected = "&5&Indent test for NovaTech v2.2."
            assert content == expected, f"notes.txt content is incorrect. Expected: '{expected}', Got: '{content}'"


def test_cpp_program_exists():
    assert os.path.exists("/home/user/compressor.cpp"), "/home/user/compressor.cpp does not exist."
    assert os.path.exists("/home/user/compressor"), "/home/user/compressor executable does not exist."
    assert os.access("/home/user/compressor", os.X_OK), "/home/user/compressor is not executable."


def expected_compression(data):
    return re.sub(rb" {2,}", lambda m: b"&" + str(len(m.group(0))).encode("ascii") + b"&", data)


def generated_cases():
    alphabet = string.ascii_letters + string.digits + "&_-"
    cases = [
        b"single spaces stay unchanged\n",
        b"  leading,   middle, and trailing spaces    ",
        b"tabs\t  do not join\t   space runs\nnext  line\n",
        b"already&4&marked but     new spaces",
        b"no_double_spaces_here",
    ]
    for _ in range(4):
        pieces = []
        for _ in range(10):
            word = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(12) + 1))
            pieces.append(word.encode("ascii"))
            pieces.append(b" " * (secrets.randbelow(24) + 1))
        pieces.append(b"end\n")
        cases.append(b"".join(pieces))
    return cases


def mode_works(executable, mode, cases):
    for index, data in enumerate(cases):
        expected = expected_compression(data)
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = os.path.join(tmpdir, f"input_{index}.txt")
            output_path = os.path.join(tmpdir, f"output_{index}.txt")
            with open(input_path, "wb") as f:
                f.write(data)

            try:
                if mode == "in_place_or_file_stdout":
                    result = subprocess.run(
                        [executable, input_path], cwd=tmpdir,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        timeout=5, check=False)
                    with open(input_path, "rb") as f:
                        resulting_file = f.read()
                    if result.returncode != 0 or not (resulting_file == expected or result.stdout == expected):
                        return False
                elif mode == "input_output_paths":
                    result = subprocess.run(
                        [executable, input_path, output_path], cwd=tmpdir,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        timeout=5, check=False)
                    if result.returncode != 0 or not os.path.isfile(output_path):
                        return False
                    with open(output_path, "rb") as f:
                        if f.read() != expected:
                            return False
                elif mode == "standard_io":
                    result = subprocess.run(
                        [executable], cwd=tmpdir, input=data,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        timeout=5, check=False)
                    if result.returncode != 0 or result.stdout != expected:
                        return False
            except (OSError, subprocess.SubprocessError):
                return False
    return True


def assert_compressor_behaves(executable, cases):
    modes = ["in_place_or_file_stdout", "input_output_paths", "standard_io"]
    assert any(mode_works(executable, mode, cases) for mode in modes), (
        f"{executable} did not correctly compress repeated ASCII spaces using "
        "an in-place, file-path, or standard-I/O interface"
    )


def test_cpp_source_and_executable_behavior():
    cases = generated_cases()

    # Exercise the submitted executable itself.
    assert_compressor_behaves("/home/user/compressor", cases)

    # Independently compile and exercise the submitted C++ source, ensuring the
    # required source file is a working implementation rather than a placeholder.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "rebuilt_compressor")
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", "/home/user/compressor.cpp", "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False)
        assert result.returncode == 0, "compressor.cpp failed to compile:\n" + result.stderr.decode("utf-8", "replace")
        assert_compressor_behaves(rebuilt, cases)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
