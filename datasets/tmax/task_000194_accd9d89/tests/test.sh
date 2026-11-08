#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import resource
import subprocess
import tempfile

REPO_DIR = "/home/user/image_processor"
BAD_COMMIT_FILE = "/home/user/bad_commit.txt"
SYSCALLS_LOG_FILE = "/home/user/syscalls.log"
CORRUPTED_FILENAME_FILE = "/home/user/corrupted_filename.txt"


def get_expected_bad_commit():
    """Retain the original assertion based on the repository history."""
    result = subprocess.run(
        ["git", "log", "--format=%H %s"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    for line in result.stdout.splitlines():
        if "Commit 142" in line:
            return line.split()[0]
    return None


def disable_core_dumps():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def compile_and_run(commit, directory):
    source = subprocess.run(
        ["git", "show", f"{commit}:main.c"],
        cwd=REPO_DIR,
        capture_output=True,
        check=True,
    ).stdout
    with open(os.path.join(directory, "main.c"), "wb") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-o", "img_proc", "main.c"],
        cwd=directory,
        capture_output=True,
        check=True,
    )
    result = subprocess.run(
        ["./img_proc"],
        cwd=directory,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        preexec_fn=disable_core_dumps,
    )
    dump_exists = os.path.isfile(os.path.join(directory, "mem_dump.bin"))
    return result.returncode == 0 and not dump_exists


def derive_first_bad_commit():
    commits = subprocess.run(
        ["git", "rev-list", "--reverse", "v2.0"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()
    assert commits, "Repository history is empty."
    assert commits[0] == subprocess.check_output(
        ["git", "rev-parse", "v1.0"], cwd=REPO_DIR, text=True
    ).strip()
    assert commits[-1] == subprocess.check_output(
        ["git", "rev-parse", "v2.0"], cwd=REPO_DIR, text=True
    ).strip()

    cache = {}
    with tempfile.TemporaryDirectory() as root:
        def is_good(index):
            if index not in cache:
                work = os.path.join(root, str(index))
                os.mkdir(work)
                cache[index] = compile_and_run(commits[index], work)
            return cache[index]

        assert is_good(0), "v1.0 is not behaviorally good."
        assert not is_good(len(commits) - 1), "v2.0 is not behaviorally bad."
        low, high = 0, len(commits) - 1
        while low + 1 < high:
            middle = (low + high) // 2
            if is_good(middle):
                low = middle
            else:
                high = middle
        assert is_good(high - 1), "Commit before derived first bad commit is not good."
        assert not is_good(high), "Derived first bad commit is not bad."
        return commits[high]


def make_reference_trace(commit):
    with tempfile.TemporaryDirectory() as work:
        source = subprocess.run(
            ["git", "show", f"{commit}:main.c"],
            cwd=REPO_DIR,
            capture_output=True,
            check=True,
        ).stdout
        with open(os.path.join(work, "main.c"), "wb") as f:
            f.write(source)
        subprocess.run(
            ["gcc", "-o", "img_proc", "main.c"],
            cwd=work,
            capture_output=True,
            check=True,
        )
        result = subprocess.run(
            ["strace", "-s", "256", "./img_proc"],
            cwd=work,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            preexec_fn=disable_core_dumps,
        )
        dump_path = os.path.join(work, "mem_dump.bin")
        assert os.path.isfile(dump_path), "First bad commit did not create mem_dump.bin."
        with open(dump_path, "rb") as f:
            dump = f.read()
        return result.stderr.decode("utf-8", errors="replace"), dump


def trace_tokens(content):
    tokens = []
    syscall_re = re.compile(
        r"^\s*(?:\[pid\s+\d+\]\s+|\d+\s+)?"
        r"(?:(?:\d\d:){2}\d\d(?:\.\d+)?\s+)?"
        r"([A-Za-z_][A-Za-z0-9_]*)\("
    )
    for line in content.splitlines():
        match = syscall_re.search(line)
        if match:
            tokens.append("CALL:" + match.group(1))
            continue
        signal = re.search(r"---\s+(SIG[A-Z0-9]+)\b", line)
        if signal:
            tokens.append("SIGNAL:" + signal.group(1))
            continue
        if re.search(r"\+\+\+\s+killed by SIGABRT", line):
            tokens.append("END:SIGABRT")
        elif re.search(r"\+\+\+\s+exited with", line):
            tokens.append("END:EXIT")
    return tokens


def test_bad_commit_txt():
    assert os.path.isfile(BAD_COMMIT_FILE), f"{BAD_COMMIT_FILE} does not exist."
    with open(BAD_COMMIT_FILE, "r") as f:
        actual_commit = f.read().strip()

    expected_commit = get_expected_bad_commit()
    assert expected_commit is not None, "Could not find 'Commit 142' in the repository history."
    assert actual_commit == expected_commit, f"Expected bad commit {expected_commit}, but found {actual_commit}."

    derived_commit = derive_first_bad_commit()
    assert actual_commit == derived_commit, (
        f"Reported commit {actual_commit} is not the behaviorally derived first bad commit {derived_commit}."
    )


def test_corrupted_filename_txt():
    assert os.path.isfile(CORRUPTED_FILENAME_FILE), f"{CORRUPTED_FILENAME_FILE} does not exist."
    with open(CORRUPTED_FILENAME_FILE, "r") as f:
        actual_filename = f.read().strip()

    expected_filename = "outpUT_CORRUPT_X99.dat"
    assert actual_filename == expected_filename, f"Expected filename '{expected_filename}', but found '{actual_filename}'."

    commit = derive_first_bad_commit()
    _, dump = make_reference_trace(commit)
    match = re.search(rb"CONFIG_STR: ([^\x00\r\n]+)", dump)
    assert match, "Fresh memory dump contains no CONFIG_STR entry."
    derived_filename = match.group(1).decode("utf-8")
    assert actual_filename == derived_filename, (
        f"Filename does not match the value extracted from a fresh first-bad-commit dump: {derived_filename}"
    )


def test_syscalls_log():
    assert os.path.isfile(SYSCALLS_LOG_FILE), f"{SYSCALLS_LOG_FILE} does not exist."
    with open(SYSCALLS_LOG_FILE, "r", errors="replace") as f:
        content = f.read()

    # Retain the original assertions.
    assert "SIGABRT" in content, "The syscalls.log does not contain 'SIGABRT', which is expected from the abort() call."
    assert "openat" in content or "open" in content, "The syscalls.log does not contain file opening syscalls."

    commit = derive_first_bad_commit()
    reference, _ = make_reference_trace(commit)
    actual_tokens = trace_tokens(content)
    reference_tokens = trace_tokens(reference)

    assert len(actual_tokens) >= 20, "syscalls.log is not a complete strace transcript."
    assert actual_tokens == reference_tokens, (
        "syscalls.log does not contain the complete syscall sequence produced by the first bad commit."
    )
    assert actual_tokens[0] == "CALL:execve", "Trace must begin with program execution."
    assert "SIGNAL:SIGABRT" in actual_tokens, "Trace lacks the delivered SIGABRT record."
    assert actual_tokens[-1] == "END:SIGABRT", "Trace must end with the process being killed by SIGABRT."

    open_match = re.search(
        r'(?:openat|open)\([^\n]*"mem_dump\.bin"[^\n]*\)\s*=\s*(\d+)', content
    )
    assert open_match, "Trace does not show mem_dump.bin being opened."
    fd = re.escape(open_match.group(1))
    assert re.search(rf"write\({fd},[^\n]*,\s*256\)\s*=\s*256", content), (
        "Trace does not show the complete 256-byte memory dump write."
    )
    assert re.search(rf"close\({fd}\)\s*=\s*0", content), (
        "Trace does not show the memory dump file being closed successfully."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
