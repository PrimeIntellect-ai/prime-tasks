#!/bin/bash
mkdir -p /logs/verifier

cat << 'PROBE_EOF' > /tmp/test_streaming.py
import os
import subprocess
import sys
import time

chunker = "/home/user/chunker.py"
docs_dir = "/home/user/organized_docs"

if not os.path.isfile(chunker):
    raise AssertionError(f"Chunker script missing at {chunker}")

subprocess.run(["rm", "-rf", docs_dir], check=True)

proc = subprocess.Popen(
    [sys.executable, chunker],
    stdin=subprocess.PIPE,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    text=True,
)

try:
    # Keep stdin open after crossing a chunk boundary. A streaming chunker must
    # emit the completed first section without waiting for end-of-file.
    probe_lines = [f"probe line {i}\n" for i in range(1, 502)]
    proc.stdin.writelines(probe_lines)
    proc.stdin.flush()

    section = os.path.join(docs_dir, "section_001.md")
    expected = "".join(probe_lines[:500])
    deadline = time.monotonic() + 5
    matched = False
    while time.monotonic() < deadline:
        try:
            with open(section, "r") as f:
                matched = f.read() == expected
        except (FileNotFoundError, OSError):
            matched = False
        if matched:
            break
        if proc.poll() is not None:
            break
        time.sleep(0.05)

    assert matched, "chunker did not emit a completed 500-line section while stdin remained open"

    proc.stdin.close()
    proc.stdin = None
    returncode = proc.wait(timeout=5)
    assert returncode == 0, f"chunker exited with status {returncode} during streaming probe"
finally:
    if proc.poll() is None:
        proc.kill()
        proc.wait()
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

DOCS_DIR = "/home/user/organized_docs"
CHUNKER_SCRIPT = "/home/user/chunker.py"


def expected_lines():
    lines = []
    for i in range(1, 2501):
        lines.extend([
            f"# Document Entry {i}\n",
            f"This is the first detail line for entry {i}.\n",
            f"This is the second detail line for entry {i}.\n",
            f"This is the third detail line for entry {i}.\n",
            f"This is the conclusion for entry {i}.\n",
        ])
    return lines


def test_chunker_script_exists():
    assert os.path.isfile(CHUNKER_SCRIPT), f"Chunker script missing at {CHUNKER_SCRIPT}"


def test_organized_docs_dir_exists():
    assert os.path.isdir(DOCS_DIR), f"Directory {DOCS_DIR} does not exist."


def test_section_files_exist_and_correct_length_and_content():
    all_expected = expected_lines()
    for i in range(1, 26):
        filename = f"section_{i:03d}.md"
        filepath = os.path.join(DOCS_DIR, filename)
        assert os.path.isfile(filepath), f"File {filename} is missing in {DOCS_DIR}."

        with open(filepath, "r") as f:
            lines = f.readlines()

        assert len(lines) == 500, f"File {filename} has {len(lines)} lines, expected exactly 500."
        start = (i - 1) * 500
        assert lines == all_expected[start:start + 500], f"File {filename} does not match the generator output."


def test_merged_index_correctness():
    index_path = os.path.join(DOCS_DIR, "merged_index.md")
    assert os.path.isfile(index_path), f"merged_index.md is missing in {DOCS_DIR}."

    with open(index_path, "r") as f:
        index_lines = f.readlines()

    assert len(index_lines) == 25, f"merged_index.md has {len(index_lines)} lines, expected exactly 25."

    for i in range(1, 26):
        expected_entry = ((i - 1) * 100) + 1
        expected_line = f"# Document Entry {expected_entry}\n"
        actual_line = index_lines[i - 1]
        assert actual_line == expected_line, (
            f"merged_index.md line {i} is incorrect. "
            f"Expected '{expected_line.strip()}', got '{actual_line.strip()}'."
        )

        section_path = os.path.join(DOCS_DIR, f"section_{i:03d}.md")
        with open(section_path, "r") as section_file:
            assert actual_line == section_file.readline(), (
                f"merged_index.md line {i} is not the first line of section_{i:03d}.md."
            )
TEST_EOF

verify() {
    python3 /tmp/test_streaming.py || return 1
    rm -rf /home/user/organized_docs || return 1
    timeout 30s bash -o pipefail -c 'python3 /home/user/generate_docs.py | python3 /home/user/chunker.py' || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
