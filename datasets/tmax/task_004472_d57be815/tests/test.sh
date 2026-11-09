#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import os
import stat
import subprocess
import time

import pytest

SCRIPT_PATH = "/home/user/clean_and_backup.py"
CLEAN_CORPUS = "/app/corpora/clean"
EVIL_CORPUS = "/app/corpora/evil"
SUMMARY_PATH = "/home/user/backup_summary.txt"
ANALYZER = "/app/analyzer"
REAL_ANALYZER = "/app/analyzer.real"
CALL_LOG = "/tmp/analyzer_calls.log"

EXPECTED_CLEAN = {
    "dir1": ("dir",),
    "dir1/file3.txt": ("file", b"test3\n"),
    "file1.txt": ("file", b"test1\n"),
    "file2.txt": ("file", b"test2\n"),
    "nested_sym.txt": ("link", "sym1.txt"),
    "sym1.txt": ("link", "file1.txt"),
    "symdir": ("link", "dir1"),
}
EXPECTED_EVIL = {
    "a.txt": ("link", "b.txt"),
    "b.txt": ("link", "a.txt"),
    "deep_a.txt": ("link", "dir2/c.txt"),
    "dir2": ("dir",),
    "dir2/c.txt": ("link", "../deep_a.txt"),
    "self.txt": ("link", "self.txt"),
}
EXPECTED_EVIL_AFTER = {"dir2": ("dir",)}
EXPECTED_FILE_ENTRIES = [
    os.path.join(CLEAN_CORPUS, "file1.txt"),
    os.path.join(CLEAN_CORPUS, "file2.txt"),
    os.path.join(CLEAN_CORPUS, "sym1.txt"),
    os.path.join(CLEAN_CORPUS, "nested_sym.txt"),
    os.path.join(CLEAN_CORPUS, "dir1/file3.txt"),
]
BASELINE_INODES = {}


def tree_snapshot(root):
    result = {}

    def visit(directory, prefix=""):
        for entry in os.scandir(directory):
            rel = os.path.join(prefix, entry.name)
            if entry.is_symlink():
                result[rel] = ("link", os.readlink(entry.path))
            elif entry.is_dir(follow_symlinks=False):
                result[rel] = ("dir",)
                visit(entry.path, rel)
            elif entry.is_file(follow_symlinks=False):
                with open(entry.path, "rb") as f:
                    result[rel] = ("file", f.read())
            else:
                result[rel] = ("other",)

    visit(root)
    return result


def run_script(target, timeout=15):
    try:
        return subprocess.run(
            ["python3", SCRIPT_PATH, target],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script timed out while processing {target}.")
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Script failed while processing {target}:\n"
            f"STDOUT: {e.stdout}\nSTDERR: {e.stderr}"
        )


@pytest.fixture(scope="session", autouse=True)
def execute_student_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist or is not a regular file."
    mode = os.stat(SCRIPT_PATH).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "Student script is not executable."

    assert tree_snapshot(CLEAN_CORPUS) == EXPECTED_CLEAN, "Clean corpus was altered before verification."
    assert tree_snapshot(EVIL_CORPUS) == EXPECTED_EVIL, "Evil corpus was altered before verification."

    for path in EXPECTED_FILE_ENTRIES:
        st = os.stat(path)
        BASELINE_INODES[path] = (st.st_dev, st.st_ino)

    assert os.path.isfile(ANALYZER) and os.access(ANALYZER, os.X_OK), "Analyzer is missing."
    assert not os.path.exists(REAL_ANALYZER), f"Unexpected path already exists: {REAL_ANALYZER}"
    os.rename(ANALYZER, REAL_ANALYZER)
    with open(ANALYZER, "w") as f:
        f.write("#!/bin/sh\nprintf '%s\\n' \"$1\" >> /tmp/analyzer_calls.log\nexec /app/analyzer.real \"$@\"\n")
    os.chmod(ANALYZER, 0o755)

    try:
        for path in (SUMMARY_PATH, CALL_LOG):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        run_script(CLEAN_CORPUS)
        run_script(EVIL_CORPUS)
        yield
    finally:
        try:
            os.unlink(ANALYZER)
        except FileNotFoundError:
            pass
        if os.path.exists(REAL_ANALYZER):
            os.rename(REAL_ANALYZER, ANALYZER)


def test_script_is_executable():
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "Student artifact is not a regular file."
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "Student script is not executable."


def test_clean_corpus_preserved():
    assert os.path.exists(CLEAN_CORPUS), f"Clean corpus directory {CLEAN_CORPUS} is missing."
    items = os.listdir(CLEAN_CORPUS)
    assert len(items) > 0, "Clean corpus appears to be empty; files were incorrectly deleted."
    assert tree_snapshot(CLEAN_CORPUS) == EXPECTED_CLEAN, "Clean files, directories, or valid symlinks were modified."

    for path, inode in BASELINE_INODES.items():
        st = os.stat(path)
        assert (st.st_dev, st.st_ino) == inode, f"Regular file represented by {path} was not preserved."

    for root, dirs, files in os.walk(CLEAN_CORPUS):
        for name in dirs + files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                assert os.path.exists(path), f"Valid symlink {path} is broken or was incorrectly modified."


def test_evil_corpus_sanitized():
    assert os.path.exists(EVIL_CORPUS), f"Evil corpus directory {EVIL_CORPUS} is missing."

    for root, dirs, files in os.walk(EVIL_CORPUS):
        for name in dirs + files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                assert os.path.exists(path), f"Cyclic or broken symlink {path} was not deleted."

    assert tree_snapshot(EVIL_CORPUS) == EXPECTED_EVIL_AFTER, "Cyclic links were not removed precisely."


def test_analyzer_was_run_for_every_valid_file_and_output_was_logged():
    assert os.path.exists(CALL_LOG), "No analyzer invocations were recorded."
    with open(CALL_LOG) as f:
        calls = [line.rstrip("\n") for line in f]

    assert len(calls) == len(EXPECTED_FILE_ENTRIES), "Analyzer invocation count is incorrect."
    actual_identities = []
    for argument in calls:
        assert os.path.isabs(argument), f"Analyzer received a non-absolute path: {argument}"
        assert os.path.isfile(argument), f"Analyzer received a path that is not a valid regular file: {argument}"
        st = os.stat(argument)
        actual_identities.append((st.st_dev, st.st_ino))

    expected_identities = [BASELINE_INODES[path] for path in EXPECTED_FILE_ENTRIES]
    assert collections.Counter(actual_identities) == collections.Counter(expected_identities), \
        "Analyzer was not invoked once for every valid regular-file entry."

    assert os.path.exists(SUMMARY_PATH), f"Backup summary not found at {SUMMARY_PATH}"
    with open(SUMMARY_PATH) as f:
        lines = f.readlines()
    expected_lines = [f"Analyzed: {argument}\n" for argument in calls]
    assert collections.Counter(lines) == collections.Counter(expected_lines), \
        "Summary does not contain the analyzer's actual output."


def test_backup_summary_created_and_populated():
    assert os.path.exists(SUMMARY_PATH), f"Backup summary not found at {SUMMARY_PATH}"
    with open(SUMMARY_PATH, "r") as f:
        lines = f.readlines()

    valid_files = 0
    for corpus in [CLEAN_CORPUS, EVIL_CORPUS]:
        for root, dirs, files in os.walk(corpus):
            for name in files:
                path = os.path.join(root, name)
                if os.path.isfile(path):
                    valid_files += 1

    assert len(lines) == valid_files, f"Expected {valid_files} lines in summary, got {len(lines)}"


def test_summary_append_honors_exclusive_file_lock(tmp_path):
    target = tmp_path / "locking_corpus"
    target.mkdir()
    sample = target / "sample.txt"
    sample.write_text("locking test\n")

    open(CALL_LOG, "w").close()
    with open(SUMMARY_PATH, "w+") as held:
        fcntl.flock(held.fileno(), fcntl.LOCK_EX)
        proc = subprocess.Popen(
            ["python3", SCRIPT_PATH, str(target)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(1.0)
        assert proc.poll() is None, "Script appended without respecting an exclusive lock on the summary file."
        fcntl.flock(held.fileno(), fcntl.LOCK_UN)

    try:
        stdout, stderr = proc.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        pytest.fail("Script did not finish after the summary lock was released.")
    assert proc.returncode == 0, f"Locking test failed:\nSTDOUT: {stdout}\nSTDERR: {stderr}"

    with open(CALL_LOG) as f:
        calls = [line.rstrip("\n") for line in f]
    assert calls == [str(sample)], "Analyzer was not called correctly during the locking test."
    with open(SUMMARY_PATH) as f:
        assert f.readlines() == [f"Analyzed: {sample}\n"], "Locked append did not preserve analyzer output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
