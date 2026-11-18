#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import hashlib
import os
import subprocess
import tempfile
import time

STORAGE_POOL = "/home/user/storage_pool"
MANIFEST_PATH = "/home/user/manifest.txt"
INDEXER_SRC = "/home/user/indexer.cpp"
INDEXER_BIN = "/home/user/indexer"
REPORT_PATH = "/home/user/storage_report.log"

EXPECTED_FILES = {
    os.path.join(STORAGE_POOL, "projectA", "main.cpp"): b'''#include <iostream>\n// QUOTA_CHECKED\nint main() {\n    return 0;\n}\n''',
    os.path.join(STORAGE_POOL, "projectB", "utils.cpp"): b'''// QUOTA_CHECKED\n// Just a utility file\nvoid do_nothing() {}\n''',
    os.path.join(STORAGE_POOL, "projectB", "data.cpp"): b'''// No quota here\nint data = 42;\n''',
}

ORIGINAL_INDEXER = '''#include <iostream>
#include <fstream>
#include <string>
#include <unistd.h>
#include <fcntl.h>
// MISSING: include for flock

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <manifest_file>\\n";
        return 1;
    }

    std::ifstream manifest(argv[1]);
    int count = 0;
    std::string line;
    while (std::getline(manifest, line)) {
        if (!line.empty()) count++;
    }

    int fd = open("/home/user/storage_report.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 1;

    // flock requires the missing header
    if (flock(fd, LOCK_EX) == -1) {
        return 1;
    }

    std::string output = "Total verified files: " + std::to_string(count) + "\\n";
    write(fd, output.c_str(), output.length());

    flock(fd, LOCK_UN);
    close(fd);

    return 0;
}
'''


def test_symlink_removed():
    symlink_path = os.path.join(STORAGE_POOL, "projectA", "loop_dir")
    assert not os.path.islink(symlink_path), f"Recursive symlink still exists at {symlink_path}"
    assert not os.path.exists(symlink_path), f"Path {symlink_path} should be completely removed"


def test_files_renamed_and_content_updated():
    cpp_files = []
    for root, dirs, files in os.walk(STORAGE_POOL):
        for name in files:
            path = os.path.join(root, name)
            assert not name.endswith(".cpp.old_backup"), f"Found unrenamed backup file: {path}"
            if name.endswith(".cpp"):
                cpp_files.append(path)

    assert len(cpp_files) == 3, f"Expected 3 .cpp files, found {len(cpp_files)}"
    assert set(cpp_files) == set(EXPECTED_FILES), "The original source paths were not preserved"

    for cpp_file in cpp_files:
        with open(cpp_file, "rb") as f:
            content = f.read()
        assert content == EXPECTED_FILES[cpp_file], f"Original transformed contents were not preserved in {cpp_file}"
        assert b"// TODO: STORAGE_QUOTA" not in content, f"Unreplaced string found in {cpp_file}"
        if cpp_file.endswith(("main.cpp", "utils.cpp")):
            assert b"// QUOTA_CHECKED" in content, f"Expected replacement string missing in {cpp_file}"


def test_manifest_generation():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"

    cpp_files = []
    for root, dirs, files in os.walk(STORAGE_POOL):
        for name in files:
            if name.endswith(".cpp"):
                cpp_files.append(os.path.join(root, name))
    cpp_files.sort()

    expected_lines = []
    for cpp_file in cpp_files:
        with open(cpp_file, "rb") as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        expected_lines.append(f"{file_hash}  {cpp_file}")

    with open(MANIFEST_PATH, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, "Manifest contents do not match expected hashes, formatting, or path sorting"


def test_indexer_fixed_and_compiled():
    assert os.path.isfile(INDEXER_SRC), f"Indexer source missing at {INDEXER_SRC}"
    with open(INDEXER_SRC, "r") as f:
        content = f.read()
    assert "<sys/file.h>" in content, f"{INDEXER_SRC} does not include <sys/file.h>"

    lines = content.splitlines(keepends=True)
    include_lines = [i for i, line in enumerate(lines) if line.strip() == "#include <sys/file.h>"]
    assert len(include_lines) == 1, "Expected exactly one standalone #include <sys/file.h> directive"
    without_header = "".join(line for i, line in enumerate(lines) if i not in include_lines)
    allowed_without_header = {
        ORIGINAL_INDEXER,
        ORIGINAL_INDEXER.replace("// MISSING: include for flock\n", ""),
    }
    assert without_header in allowed_without_header, "indexer.cpp changed beyond adding the required flock header"

    assert os.path.isfile(INDEXER_BIN), f"Compiled indexer binary missing at {INDEXER_BIN}"
    assert os.access(INDEXER_BIN, os.X_OK), f"Compiled indexer at {INDEXER_BIN} is not executable"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "indexer")
        result = subprocess.run(
            ["g++", INDEXER_SRC, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"Fixed indexer.cpp does not compile: {result.stderr}"
        with open(rebuilt, "rb") as f:
            rebuilt_bytes = f.read()
        with open(INDEXER_BIN, "rb") as f:
            submitted_bytes = f.read()
        assert submitted_bytes == rebuilt_bytes, "The executable was not produced from the fixed indexer.cpp using the requested command"


def test_report_generated_and_indexer_runs_with_locking():
    assert os.path.isfile(REPORT_PATH), f"Report file missing at {REPORT_PATH}"

    expected_content = f"Total verified files: {len(EXPECTED_FILES)}\n"
    with open(REPORT_PATH, "r") as f:
        actual_content = f.read()
    assert actual_content == expected_content, f"Report content mismatch. Expected {expected_content!r}, got {actual_content!r}"

    dynamic_count = 5 + (os.urandom(1)[0] % 7)
    with tempfile.NamedTemporaryFile("w", delete=False) as manifest:
        dynamic_manifest = manifest.name
        for i in range(dynamic_count):
            manifest.write(f"verifier-generated-line-{i}-{os.urandom(8).hex()}\n")

    try:
        lock_fd = os.open(REPORT_PATH, os.O_RDWR)
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        proc = subprocess.Popen(
            [INDEXER_BIN, dynamic_manifest],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(0.3)
        assert proc.poll() is None, "Indexer did not wait for an exclusive lock on the report"
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)
        stdout, stderr = proc.communicate(timeout=5)
        assert proc.returncode == 0, f"Indexer failed on verifier manifest: {stdout}{stderr}"

        with open(REPORT_PATH, "r") as f:
            assert f.read() == f"Total verified files: {dynamic_count}\n", "Indexer did not derive the report from its manifest argument"

        result = subprocess.run(
            [INDEXER_BIN, MANIFEST_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, f"Indexer failed on the submitted manifest: {result.stdout}{result.stderr}"
        with open(REPORT_PATH, "r") as f:
            assert f.read() == expected_content, "Indexer did not regenerate the correct final report"
    finally:
        if 'proc' in locals() and proc.poll() is None:
            proc.kill()
            proc.wait()
        if 'lock_fd' in locals():
            try:
                os.close(lock_fd)
            except OSError:
                pass
        os.unlink(dynamic_manifest)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
