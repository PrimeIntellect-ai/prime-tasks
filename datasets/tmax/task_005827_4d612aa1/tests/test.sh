#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import secrets
import subprocess
import time


def expected_standard_csv():
    return (
        "Alice,API_Reference,Draft\n"
        "Bob,User_Guide,Review\n"
        "Charlie,Release_Notes,Final\n"
    )


def expected_standard_txt():
    return (
        "[Draft] API_Reference updated by Alice\n"
        "[Review] User_Guide updated by Bob\n"
        "[Final] Release_Notes updated by Charlie\n"
    )


def expected_standard_bin():
    return b"API_Reference\0User_Guide\0Release_Notes\0"


def clear_registries():
    for path in ("/home/user/registry.txt", "/home/user/registry.bin"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def assert_outputs(expected_txt, expected_bin):
    with open("/home/user/registry.txt", "rb") as f:
        assert f.read() == expected_txt.encode(), "processor generated incorrect registry.txt"
    with open("/home/user/registry.bin", "rb") as f:
        assert f.read() == expected_bin, "processor generated incorrect registry.bin"


def test_archive_integrity():
    result = subprocess.run(
        ["gzip", "-t", "/home/user/docs.tar.gz"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, "docs.tar.gz failed gzip integrity verification"


def test_docs_extracted():
    extracted_file = "/home/user/docs/draft_logs.txt"
    assert os.path.isfile(extracted_file), f"{extracted_file} does not exist. Archive was not extracted correctly."


def test_parsed_logs_csv():
    csv_path = "/home/user/parsed_logs.csv"
    assert os.path.isfile(csv_path), f"{csv_path} does not exist."

    expected_csv = expected_standard_csv()
    with open(csv_path, "r") as f:
        content = f.read().strip() + "\n"

    assert content == expected_csv, "The contents of parsed_logs.csv do not match the expected output."


def test_processor_cpp_locking():
    cpp_path = "/home/user/processor.cpp"
    assert os.path.isfile(cpp_path), f"{cpp_path} does not exist."

    with open(cpp_path, "r") as f:
        content = f.read()

    has_headers = "<sys/file.h>" in content or "<fcntl.h>" in content
    assert has_headers, "processor.cpp does not include <sys/file.h> or <fcntl.h> for file locking."

    has_locking = "flock(" in content or "F_SETLK" in content or "F_SETLKW" in content
    assert has_locking, "processor.cpp does not seem to use flock or fcntl for file locking."


def test_registry_txt():
    txt_path = "/home/user/registry.txt"
    assert os.path.isfile(txt_path), f"{txt_path} does not exist."

    expected_txt = expected_standard_txt()
    with open(txt_path, "r") as f:
        content = f.read().strip() + "\n"

    assert content == expected_txt, "The contents of registry.txt do not match the expected output."


def test_registry_bin():
    bin_path = "/home/user/registry.bin"
    assert os.path.isfile(bin_path), f"{bin_path} does not exist."

    expected_bin = expected_standard_bin()
    with open(bin_path, "rb") as f:
        content = f.read()

    assert content == expected_bin, "The contents of registry.bin do not match the expected binary output."


def test_compile_execute_and_real_locking():
    csv_path = "/home/user/parsed_logs.csv"
    exe_path = "/home/user/processor"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "/home/user/processor.cpp", "-o", exe_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, f"processor.cpp did not compile:\n{compile_result.stderr}"
    assert os.path.isfile(exe_path), "Compilation did not create /home/user/processor"
    assert os.access(exe_path, os.X_OK), "/home/user/processor is not executable"

    # Remove the submitted outputs and prove the freshly compiled artifact can
    # generate the required outputs from the required CSV.
    clear_registries()
    run_result = subprocess.run([exe_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert run_result.returncode == 0, "The compiled processor failed when executed"
    assert_outputs(expected_standard_txt(), expected_standard_bin())

    original_csv = expected_standard_csv()
    token = secrets.token_hex(8)
    author = "Author_" + token
    doc = "Document_" + token
    status = "Status_" + token
    dynamic_csv = f"{author},{doc},{status}\n"
    dynamic_txt = f"[{status}] {doc} updated by {author}\n"
    dynamic_bin = doc.encode() + b"\0"

    lock_file = None
    child = None
    try:
        with open(csv_path, "w") as f:
            f.write(dynamic_csv)

        clear_registries()
        lock_file = open("/home/user/registry.txt", "w+b")
        # Hold both lock namespaces so a valid implementation using either
        # flock or fcntl must wait before writing the text record.
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX)

        child = subprocess.Popen([exe_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(0.5)
        assert child.poll() is None, "processor did not wait for the exclusive registry lock"
        lock_file.seek(0)
        assert lock_file.read() == b"", "processor wrote registry.txt without obtaining the lock"
        assert not os.path.exists("/home/user/registry.bin") or os.path.getsize("/home/user/registry.bin") == 0, \
            "processor advanced past the locked text write"

        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()
        lock_file = None

        stdout, stderr = child.communicate(timeout=10)
        assert child.returncode == 0, f"processor failed after the lock was released: {stderr.decode(errors='replace')}"
        child = None
        assert_outputs(dynamic_txt, dynamic_bin)
    finally:
        if child is not None and child.poll() is None:
            child.kill()
            child.wait()
        if lock_file is not None:
            try:
                fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            finally:
                lock_file.close()

        # Leave all required final artifacts in their specified state.
        with open(csv_path, "w") as f:
            f.write(original_csv)
        clear_registries()
        restored = subprocess.run([exe_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert restored.returncode == 0, "processor failed while restoring required final outputs"

    assert_outputs(expected_standard_txt(), expected_standard_bin())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
