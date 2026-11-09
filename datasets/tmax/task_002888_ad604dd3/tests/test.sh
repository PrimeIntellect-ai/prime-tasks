#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import secrets
import shutil
import subprocess
import tarfile

import pytest

SOURCE = "/home/user/doc_parser.c"
BINARY = "/tmp/doc_parser_verified"
MANUAL = "/home/user/legacy_manual.gz"
RECOVERED = "/home/user/recovered_docs"

EXPECTED_FILES = {
    "getting_started.txt": "Welcome to the system.\nIt is very easy to use.\n© 2023 Corporation.\n",
    "advanced_config.txt": "Advanced settings:\n- Set proxy to 127.0.0.1\n- ¿Que pasa?\n",
    "troubleshooting.txt": "If it breaks, try turning it off and on.\nError æ is fatal.\n",
}


def test_doc_parser_c_exists():
    """Verify the C program was created."""
    assert os.path.exists(SOURCE), "The C program /home/user/doc_parser.c is missing."


def test_program_compiles_uses_required_libraries_and_processes_stream():
    """Compile and execute the submitted C source against independently generated input."""
    subprocess.run(
        ["gcc", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY, "-lz"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    symbols = subprocess.run(
        ["nm", "-D", BINARY],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    ).stdout
    assert re.search(r"\bgzopen(?:64)?(?:@|\b)", symbols), "Compiled program does not use zlib gzopen."
    assert re.search(r"\bgz(?:gets|read|getc)(?:@|\b)", symbols), "Compiled program does not stream data through a zlib gz read API."
    assert re.search(r"\biconv_open(?:@|\b)", symbols), "Compiled program does not initialize iconv."
    assert re.search(r"\biconv(?:@|\b)", symbols), "Compiled program does not perform conversion with iconv."

    token = secrets.token_hex(8)
    generated = {
        f"alpha_{token}.txt": f"Random page {token}.\nCopyright © and pound £.\n",
        f"middle_{token}.txt": "Una pregunta: ¿Que tal?\nLigature æ and value 42.\n",
        f"omega_{token}.txt": f"Last section {token}.\nAccents: àéöÿ.\n",
    }

    original_manual = open(MANUAL, "rb").read()
    preserved = {}
    for path in ("/home/user/clean_docs.tar.gz", "/home/user/recovery.log"):
        if os.path.exists(path):
            with open(path, "rb") as f:
                preserved[path] = f.read()

    try:
        with gzip.open(MANUAL, "wb") as f:
            for filename, content in generated.items():
                f.write(f"==== DOC_START: {filename} ====\n".encode("ISO-8859-1"))
                f.write(content.encode("ISO-8859-1"))

        shutil.rmtree(RECOVERED, ignore_errors=True)
        subprocess.run([BINARY], check=True, timeout=30, cwd="/home/user")

        assert os.path.isdir(RECOVERED), "The C program did not create recovered_docs."
        actual_names = sorted(
            name for name in os.listdir(RECOVERED)
            if os.path.isfile(os.path.join(RECOVERED, name))
        )
        assert actual_names == sorted(generated), "The C program did not split the generated gzip stream correctly."
        for filename, expected in generated.items():
            path = os.path.join(RECOVERED, filename)
            with open(path, "r", encoding="utf-8") as f:
                assert f.read() == expected
    finally:
        with open(MANUAL, "wb") as f:
            f.write(original_manual)
        shutil.rmtree(RECOVERED, ignore_errors=True)
        restore = subprocess.run([BINARY], timeout=30, cwd="/home/user")
        for path, data in preserved.items():
            with open(path, "wb") as f:
                f.write(data)
        assert restore.returncode == 0, "The compiled C program failed on the original legacy_manual.gz."


def test_recovered_docs_dir_exists():
    """Verify the recovered_docs directory was created."""
    assert os.path.isdir(RECOVERED), "The directory /home/user/recovered_docs/ is missing."


def test_recovery_log():
    """Verify the recovery.log file contains the sorted filenames."""
    log_path = "/home/user/recovery.log"
    assert os.path.exists(log_path), f"The log file {log_path} is missing."

    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "advanced_config.txt",
        "getting_started.txt",
        "troubleshooting.txt"
    ]
    assert lines == expected_lines, f"The contents of {log_path} do not match the expected sorted filenames."


def test_recovered_files_content_and_encoding():
    """Verify the recovered files exist, are UTF-8 encoded, and have correct content."""
    for filename, expected_content in EXPECTED_FILES.items():
        file_path = os.path.join(RECOVERED, filename)
        assert os.path.exists(file_path), f"Recovered file missing: {file_path}"

        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
        except UnicodeDecodeError:
            pytest.fail(f"File {file_path} is not valid UTF-8.")

        assert content == expected_content, f"Content of {file_path} does not match the expected UTF-8 text."


def test_clean_docs_tarball():
    """Verify the clean_docs.tar.gz exists and contains the recovered files with correct contents."""
    tarball_path = "/home/user/clean_docs.tar.gz"
    assert os.path.exists(tarball_path), f"The tarball {tarball_path} is missing."
    assert tarfile.is_tarfile(tarball_path), f"{tarball_path} is not a valid tar archive."

    with tarfile.open(tarball_path, "r:gz") as tar:
        names = tar.getnames()
        basenames = [os.path.basename(name) for name in names if not name.endswith('/')]

        expected_names = [
            "advanced_config.txt",
            "getting_started.txt",
            "troubleshooting.txt"
        ]
        for ef in expected_names:
            assert ef in basenames, f"File {ef} is missing from the tarball {tarball_path}."

        for filename, expected_content in EXPECTED_FILES.items():
            matches = []
            for member in tar.getmembers():
                normalized = member.name
                while normalized.startswith("./"):
                    normalized = normalized[2:]
                if normalized in (filename, f"recovered_docs/{filename}"):
                    matches.append(member)
            assert len(matches) == 1, f"Tarball must contain exactly one valid copy of {filename}."
            member = matches[0]
            assert member.isfile(), f"Archived entry {member.name} is not a regular file."
            archived = tar.extractfile(member).read()
            try:
                archived_text = archived.decode("utf-8")
            except UnicodeDecodeError:
                pytest.fail(f"Archived file {member.name} is not valid UTF-8.")
            assert archived_text == expected_content, f"Archived content of {filename} is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
