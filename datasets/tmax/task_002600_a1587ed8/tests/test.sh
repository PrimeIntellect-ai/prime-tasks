#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys

OUTPUT_FILE = "/home/user/extracted_comments.txt"
SCRIPT_FILE = "/home/user/extract.py"


def test_extracted_comments_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."


def test_extracted_comments_content():
    expected_lines = [
        "Begin finishing pass",
        "Cut at 45° angle",
        "End of job",
        "Initialize spindlé"
    ]

    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            content = f.read().splitlines()
    except UnicodeDecodeError:
        assert False, f"Output file {OUTPUT_FILE} is not properly encoded in UTF-8."

    assert content == expected_lines, f"Content of {OUTPUT_FILE} does not match expected output. Got: {content}"


def test_script_exists_and_uses_atomic_write():
    assert os.path.isfile(SCRIPT_FILE), f"Script file {SCRIPT_FILE} does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT_FILE).st_mode), f"Script file {SCRIPT_FILE} must be a regular file."

    with open(SCRIPT_FILE, "r", encoding="utf-8") as f:
        script_content = f.read()

    valid_atomic_funcs = ["os.replace", "os.rename", "shutil.move"]
    has_atomic = any(func in script_content for func in valid_atomic_funcs)
    assert has_atomic, f"Script {SCRIPT_FILE} does not appear to use an atomic write method (os.replace, os.rename, or shutil.move)."


def test_script_has_symlink_cycle_detection():
    with open(SCRIPT_FILE, "r", encoding="utf-8") as f:
        script_content = f.read()

    has_realpath = "realpath" in script_content or "abspath" in script_content or "samefile" in script_content
    has_set_or_dict = "set()" in script_content or "{" in script_content or "dict" in script_content or "[]" in script_content

    assert has_realpath and has_set_or_dict, f"Script {SCRIPT_FILE} does not appear to contain cycle detection logic tracking visited paths."


def _independent_scan(root):
    comments = []
    visited_dirs = set()

    def visit(path):
        st = os.stat(path, follow_symlinks=True)
        key = (st.st_dev, st.st_ino)
        if key in visited_dirs:
            return
        visited_dirs.add(key)

        for entry in os.scandir(path):
            try:
                if entry.is_dir(follow_symlinks=True):
                    visit(entry.path)
                elif entry.name.endswith(".gcode") and entry.is_file(follow_symlinks=True):
                    with open(entry.path, "r", encoding="cp1252") as f:
                        for line in f:
                            stripped = line.lstrip()
                            if stripped.startswith(";"):
                                comments.append(stripped[1:].strip())
            except FileNotFoundError:
                pass

    visit(root)
    return sorted(comments)


def test_script_executes_on_dynamic_archive_and_writes_atomically():
    token = secrets.token_hex(10)
    local_dir = os.path.join("/home/user/cnc_docs", "dynamic_" + token)
    external_dir = os.path.join("/tmp", "cnc_external_" + token)
    os.makedirs(local_dir)
    os.makedirs(external_dir)

    local_comments = [f"Alpha £ fixture {token}", f"Zéta local {token}"]
    external_comments = [f"Beta external {token}", f"Tool at 90° {token}"]

    with open(os.path.join(local_dir, "local.gcode"), "w", encoding="cp1252", newline="") as f:
        f.write("G21 ; inline text must be ignored\r\n")
        f.write("   ; " + local_comments[1] + "   \r\n")
        f.write(";" + local_comments[0] + "\r\n")
        f.write("M30\r\n")

    with open(os.path.join(external_dir, "linked.gcode"), "w", encoding="cp1252", newline="") as f:
        f.write("\t; " + external_comments[0] + "\r\n")
        f.write("; " + external_comments[1] + "  \r\n")
        f.write("G00 X0 ; ignored inline comment\r\n")

    with open(os.path.join(external_dir, "ignored.txt"), "w", encoding="cp1252") as f:
        f.write("; This is not from a gcode file\n")

    os.symlink(external_dir, os.path.join(local_dir, "linked_external"))
    os.symlink("/home/user/cnc_docs", os.path.join(external_dir, "back_to_archive"))

    expected = _independent_scan("/home/user/cnc_docs")
    for value in local_comments + external_comments:
        assert value in expected

    if os.path.lexists(OUTPUT_FILE):
        os.unlink(OUTPUT_FILE)

    hook_dir = os.path.join("/tmp", "atomic_hook_" + token)
    os.makedirs(hook_dir)
    log_file = os.path.join(hook_dir, "atomic.log")
    hook = r'''
import json
import os
import shutil

_target = os.path.abspath(os.environ["VERIFY_ATOMIC_TARGET"])
_expected = json.loads(os.environ["VERIFY_EXPECTED"])
_log = os.environ["VERIFY_ATOMIC_LOG"]
_orig_replace = os.replace
_orig_rename = os.rename
_orig_move = shutil.move


def _qualifies(src, dst):
    try:
        src_path = os.path.abspath(os.fspath(src))
        dst_path = os.path.abspath(os.fspath(dst))
        if src_path == dst_path or dst_path != _target or not os.path.isfile(src_path):
            return False
        with open(src_path, "r", encoding="utf-8") as f:
            return f.read().splitlines() == _expected
    except Exception:
        return False


def _record():
    with open(_log, "a", encoding="utf-8") as f:
        f.write("atomic-final-write\n")


def checked_replace(src, dst, *args, **kwargs):
    good = _qualifies(src, dst)
    result = _orig_replace(src, dst, *args, **kwargs)
    if good:
        _record()
    return result


def checked_rename(src, dst, *args, **kwargs):
    good = _qualifies(src, dst)
    result = _orig_rename(src, dst, *args, **kwargs)
    if good:
        _record()
    return result


def checked_move(src, dst, *args, **kwargs):
    good = _qualifies(src, dst)
    result = _orig_move(src, dst, *args, **kwargs)
    if good:
        _record()
    return result

os.replace = checked_replace
os.rename = checked_rename
shutil.move = checked_move
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(hook)

    env = os.environ.copy()
    env["PYTHONPATH"] = hook_dir
    env["VERIFY_ATOMIC_TARGET"] = OUTPUT_FILE
    env["VERIFY_EXPECTED"] = json.dumps(expected, ensure_ascii=False)
    env["VERIFY_ATOMIC_LOG"] = log_file

    result = subprocess.run(
        [sys.executable, SCRIPT_FILE],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"Executing {SCRIPT_FILE} failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert os.path.isfile(OUTPUT_FILE), "Executing the script did not create the output file."

    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            actual = f.read().splitlines()
    except UnicodeDecodeError:
        assert False, f"Output file {OUTPUT_FILE} is not properly encoded in UTF-8."

    assert actual == expected, f"Script did not traverse and parse the dynamic archive correctly. Got: {actual}"
    assert os.path.isfile(log_file), "The final output was not installed using an atomic rename/replace operation."
    with open(log_file, "r", encoding="utf-8") as f:
        assert "atomic-final-write" in f.read(), "The atomic operation did not install the complete expected output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
