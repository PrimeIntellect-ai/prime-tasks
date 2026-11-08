#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import shlex
import shutil
import subprocess
import tempfile
from pathlib import Path

USER = pwd.getpwnam("user")


def demote_to_user():
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_as_user(argv, cwd, timeout=10):
    env = os.environ.copy()
    env["HOME"] = USER.pw_dir
    env["USER"] = USER.pw_name
    env["LOGNAME"] = USER.pw_name
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=demote_to_user,
    )


def test_root_cause_identified():
    path = "/home/user/root_cause.txt"
    assert os.path.isfile(path), f"Verification failed: {path} not found."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "*", f"Verification failed: root_cause.txt does not correctly identify '*'. Found: {content}"


def test_mre_script_exists_and_reproduces_bug():
    path = "/home/user/mre.sh"
    assert os.path.isfile(path), "Verification failed: mre.sh not found."
    assert os.access(path, os.X_OK), "Verification failed: mre.sh is not executable."

    content = Path(path).read_text(errors="replace")
    assert re.search(r"(['\"])[*]\1", content) or re.search(r"=\s*\\[*](?:\s|$)", content, re.MULTILINE), \
        "Verification failed: mre.sh does not contain the exact malformed input '*'."

    # The MRE must contain the same unsafe mechanism: an unquoted parameter
    # expansion used as an argument to rm.
    unsafe_rm = False
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or not re.search(r"\brm\b", line):
            continue
        quote = None
        escaped = False
        for char in line:
            if escaped:
                escaped = False
                continue
            if char == "\\" and quote != "'":
                escaped = True
                continue
            if char in ("'", '"'):
                if quote is None:
                    quote = char
                elif quote == char:
                    quote = None
                continue
            if char == "$" and quote is None:
                unsafe_rm = True
                break
        if unsafe_rm:
            break
    assert unsafe_rm, "Verification failed: mre.sh does not reproduce the unquoted rm expansion bug."

    work = tempfile.mkdtemp(prefix="mre-check-")
    os.chown(work, USER.pw_uid, USER.pw_gid)
    try:
        result = run_as_user(["/bin/bash", "-x", path], cwd=work)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    assert result.returncode == 0, \
        f"Verification failed: mre.sh did not execute successfully.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    # bash -x prints commands after expansion. Require an rm invocation with
    # at least two resulting operands, demonstrating that one unquoted glob
    # expanded into multiple destructive arguments.
    expanded_rm = False
    for trace_line in result.stderr.splitlines():
        stripped = trace_line.lstrip("+").strip()
        if not stripped:
            continue
        try:
            words = shlex.split(stripped)
        except ValueError:
            continue
        for index, word in enumerate(words):
            if os.path.basename(word) != "rm":
                continue
            operands = [w for w in words[index + 1:] if w != "--" and not w.startswith("-")]
            if len(operands) >= 2:
                expanded_rm = True
                break
        if expanded_rm:
            break
    assert expanded_rm, \
        "Verification failed: mre.sh did not demonstrate a glob expanding into multiple rm operands."


def test_archiver_fix_no_cat_loop():
    path = "/home/user/archiver.sh"
    assert os.path.isfile(path), f"Verification failed: {path} not found."

    with open(path, "r") as f:
        content = f.read()

    assert not re.search(r"for\s+\w+\s+in\s+\$\(\s*cat", content), \
        "Verification failed: archiver.sh still uses the vulnerable for-loop construct."


def test_archiver_fix_quoted_rm():
    path = "/home/user/archiver.sh"
    assert os.path.isfile(path), f"Verification failed: {path} not found."

    with open(path, "r") as f:
        lines = f.readlines()

    for line in lines:
        if re.search(r'rm\s+[^\"]*\$file', line) or re.search(r"rm\s+[^']*\$file", line):
            pass

    with open(path, "r") as f:
        content = f.read()

    assert not re.search(r'rm\s+[^\"]*\$file', content), \
        "Verification failed: archiver.sh still contains unquoted rm arguments."


def test_archiver_behavior_with_special_filenames():
    script = "/home/user/archiver.sh"
    assert os.path.isfile(script), f"Verification failed: {script} not found."
    assert os.access(script, os.X_OK), "Verification failed: archiver.sh is not executable."

    processed = Path("/home/user/processed")
    archive = Path("/home/user/archive")
    staging = Path("/home/user/staging")

    for directory in (processed, archive, staging):
        if directory.exists() or directory.is_symlink():
            if directory.is_dir() and not directory.is_symlink():
                shutil.rmtree(directory)
            else:
                directory.unlink()
        directory.mkdir(parents=True)
        os.chown(directory, USER.pw_uid, USER.pw_gid)
        os.chmod(directory, 0o777)

    queued = {
        "ordinary.txt": b"ordinary\n",
        "space name.txt": b"space\n",
        "*": b"literal-star\n",
        "question?.txt": b"literal-question\n",
        "-leading-option": b"leading-option\n",
    }
    unqueued = {
        "questionX.txt": b"question-decoy\n",
        "unlisted.txt": b"unlisted-decoy\n",
        "another file.txt": b"space-decoy\n",
    }

    for name, data in {**queued, **unqueued}.items():
        target = processed / name
        target.write_bytes(data)
        os.chown(target, USER.pw_uid, USER.pw_gid)
        os.chmod(target, 0o666)

    queue = staging / "queue.txt"
    queue.write_text("\n".join(queued.keys()) + "\n")
    os.chown(queue, USER.pw_uid, USER.pw_gid)
    os.chmod(queue, 0o666)

    result = run_as_user([script], cwd="/home/user")
    assert result.returncode == 0, \
        f"Verification failed: archiver.sh exited with {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    assert not queue.exists(), "Verification failed: archiver.sh did not remove queue.txt after processing."

    for name, expected in queued.items():
        assert not (processed / name).exists(), \
            f"Verification failed: queued file {name!r} remains in processed."
        archived = archive / name
        assert archived.is_file(), \
            f"Verification failed: queued file {name!r} was not archived under its exact filename."
        assert archived.read_bytes() == expected, \
            f"Verification failed: archived contents for {name!r} changed."

    for name, expected in unqueued.items():
        original = processed / name
        assert original.is_file(), \
            f"Verification failed: unqueued file {name!r} was removed by expansion."
        assert original.read_bytes() == expected, \
            f"Verification failed: unqueued file {name!r} was modified."
        assert not (archive / name).exists(), \
            f"Verification failed: unqueued file {name!r} was archived."

    assert {entry.name for entry in archive.iterdir()} == set(queued), \
        "Verification failed: archive contains missing or unexpected files."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
