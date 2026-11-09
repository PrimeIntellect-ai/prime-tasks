#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat

def test_doc_watcher_exists_and_executable():
    """Verify that the C++ source and compiled executable exist, and the latter is executable."""
    cpp_file = "/home/user/doc_watcher.cpp"
    exe_file = "/home/user/doc_watcher"

    assert os.path.isfile(cpp_file), f"Source file {cpp_file} does not exist."
    assert os.path.isfile(exe_file), f"Executable {exe_file} does not exist."

    st = os.stat(exe_file)
    assert bool(st.st_mode & stat.S_IXUSR), f"{exe_file} is not executable."

def test_organized_files():
    """Verify that the organized directory contains the correctly renamed files."""
    organized_dir = "/home/user/organized"
    assert os.path.isdir(organized_dir), f"{organized_dir} directory does not exist."

    expected_files = {
        "API_Setup_Alice_Smith.md",
        "Database_Config_Bob_Jones.md",
        "User_Auth_Alice_Smith.md"
    }

    actual_files = set(os.listdir(organized_dir))
    missing = expected_files - actual_files
    assert not missing, f"Expected files missing from {organized_dir}: {missing}"

def test_staging_directory_empty_of_drafts():
    """Verify that the staging directory no longer contains the original draft files."""
    staging_dir = "/home/user/staging"
    assert os.path.isdir(staging_dir), f"{staging_dir} directory does not exist."

    files = set(os.listdir(staging_dir))
    drafts = {"draft1.md", "draft2.md", "draft3.md"}
    remaining = drafts.intersection(files)
    assert not remaining, f"Draft files should have been moved from {staging_dir}, but found: {remaining}"

def test_final_listing_log():
    """Verify that final_listing.log contains the correct sorted filenames."""
    log_file = "/home/user/final_listing.log"
    assert os.path.isfile(log_file), f"{log_file} does not exist."

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "API_Setup_Alice_Smith.md",
        "Database_Config_Bob_Jones.md",
        "User_Auth_Alice_Smith.md"
    ]

    assert lines == expected_lines, f"Contents of {log_file} do not match expected output. Got: {lines}"
TEST_EOF

cat << 'BEHAVIOR_EOF' > /tmp/test_doc_watcher_behavior.py
import os
import shutil
import stat
import subprocess
import time
import uuid

EXE = "/home/user/doc_watcher"
SOURCE = "/home/user/doc_watcher.cpp"
STAGING = "/home/user/staging"
ORGANIZED = "/home/user/organized"


def wait_for(predicate, timeout, description):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for {description}")


assert os.path.isfile(SOURCE), f"Missing source file: {SOURCE}"
assert os.path.isfile(EXE), f"Missing executable: {EXE}"
assert os.stat(EXE).st_mode & stat.S_IXUSR, f"Not executable: {EXE}"
with open(EXE, "rb") as f:
    assert f.read(4) == b"\x7fELF", "doc_watcher must be a compiled executable"

compile_result = subprocess.run(
    ["g++", "-std=c++17", SOURCE, "-o", "/tmp/doc_watcher_recompiled"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert compile_result.returncode == 0, f"Source does not compile with g++ -std=c++17:\n{compile_result.stderr}"

# Stop any leftover watcher before creating a fresh, unpredictable test state.
subprocess.run(["pkill", "-x", "doc_watcher"], stdout=subprocess.DEVNULL,
               stderr=subprocess.DEVNULL, check=False)
time.sleep(0.2)
shutil.rmtree(STAGING, ignore_errors=True)
shutil.rmtree(ORGANIZED, ignore_errors=True)

token = uuid.uuid4().hex[:10]
cases = [
    (f"incoming_{token}_one.md", f"Audit {token} Writer", f"Fresh Topic {token}", "first body\n"),
    (f"incoming_{token}_two.md", f"Second Author {token}", f"Runtime Check {token}", "second body\nmore text\n"),
    (f"incoming_{token}_three.md", f"Third {token} Person", f"Polling Test {token}", "third body\n"),
]

proc = subprocess.Popen([EXE], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
try:
    wait_for(lambda: os.path.isdir(STAGING) and os.path.isdir(ORGANIZED), 4,
             "the watcher to create staging and organized directories")
    assert proc.poll() is None, "doc_watcher exited before receiving HALT"

    expected = {}
    # Supply files one at a time, including files that arrive after earlier work completed.
    for source_name, author, topic, body in cases:
        source_path = os.path.join(STAGING, source_name)
        content = f"Author: {author}\nTopic: {topic}\n{body}"
        destination_name = f"{topic.replace(' ', '_')}_{author.replace(' ', '_')}.md"
        destination_path = os.path.join(ORGANIZED, destination_name)
        expected[destination_name] = content

        with open(source_path, "w") as f:
            f.write(content)

        wait_for(lambda p=destination_path: os.path.isfile(p), 5,
                 f"processing of newly supplied file {source_name}")
        assert not os.path.exists(source_path), f"{source_name} was not moved out of staging"
        with open(destination_path, "r") as f:
            assert f.read() == content, f"Contents changed while moving {source_name}"
        assert proc.poll() is None, "doc_watcher stopped before HALT was supplied"

    actual = set(os.listdir(ORGANIZED))
    assert actual == set(expected), f"Unexpected organized filenames: {actual}; expected: {set(expected)}"

    halt_path = os.path.join(STAGING, "HALT")
    with open(halt_path, "w"):
        pass
    try:
        return_code = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        raise AssertionError("doc_watcher did not exit after HALT appeared")
    stderr = proc.stderr.read() if proc.stderr else ""
    assert return_code == 0, f"doc_watcher did not exit cleanly after HALT (code {return_code}): {stderr}"
finally:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
BEHAVIOR_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_doc_watcher_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
