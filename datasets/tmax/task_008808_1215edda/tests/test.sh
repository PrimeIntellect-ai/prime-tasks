#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import secrets
import stat
import subprocess
import pytest

HOOK_SOURCE = "/home/user/hook.c"
HOOK_PATH = "/home/user/alerts.git/hooks/post-receive"
LOG_PATH = "/home/user/push.log"
EXPECT_SCRIPT = "/home/user/push_test.exp"
BARE_REPO = "/home/user/alerts.git"
DUMMY_REPO = "/home/user/dummy_repo"


def run_as_user(args, cwd=None, check=False, **kwargs):
    command = ["runuser", "-u", "user", "--", "env", "HOME=/home/user"] + list(args)
    return subprocess.run(command, cwd=cwd, check=check, **kwargs)


def exercise_hook(executable):
    existed = os.path.exists(LOG_PATH)
    old_content = open(LOG_PATH, "rb").read() if existed else None
    marker = ("preexisting-" + secrets.token_hex(12) + "\n").encode()

    refs = [
        f"refs/heads/audit-{secrets.token_hex(8)}",
        f"refs/heads/nested/{secrets.token_hex(7)}",
        f"refs/tags/check-{secrets.token_hex(9)}",
        f"refs/remotes/check/{secrets.token_hex(6)}",
    ]
    records = []
    for refname in refs:
        oldrev = secrets.token_hex(20)
        newrev = secrets.token_hex(20)
        records.append(f"{oldrev} {newrev} {refname}\n")

    try:
        with open(LOG_PATH, "wb") as f:
            f.write(marker)

        process = subprocess.run(
            [executable],
            input="".join(records),
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert process.returncode == 0, (
            f"Hook execution failed: stdout={process.stdout!r}, stderr={process.stderr!r}"
        )
        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created by the hook"

        expected = marker + b"".join(
            f"[MONITOR] {refname} updated\n".encode() for refname in refs
        )
        with open(LOG_PATH, "rb") as f:
            actual = f.read()
        assert actual == expected, (
            "Hook must append exactly one correctly formatted line for every input line"
        )
        assert f"[MONITOR] {refs[0]} updated".encode() in actual
    finally:
        if existed:
            with open(LOG_PATH, "wb") as f:
                f.write(old_content)
        elif os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)


def test_hook_executable_exists():
    assert os.path.isfile(HOOK_PATH), f"Hook executable not found at {HOOK_PATH}"
    st = os.stat(HOOK_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Hook at {HOOK_PATH} is not executable"
    with open(HOOK_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Installed hook must be a compiled executable"


def test_c_source_exists_compiles_and_works(tmp_path):
    assert os.path.isfile(HOOK_SOURCE), f"C source not found at {HOOK_SOURCE}"
    with open(HOOK_SOURCE, "rb") as f:
        source = f.read()
    assert b"\x00" not in source, "hook.c is not a text C source file"

    rebuilt = tmp_path / "post-receive-from-source"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", HOOK_SOURCE, "-o", str(rebuilt)],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"hook.c does not compile: {compile_result.stderr}"
    )
    exercise_hook(str(rebuilt))


def test_installed_hook_functionality():
    exercise_hook(HOOK_PATH)


def test_expect_script_executes_real_push():
    assert os.path.isfile(EXPECT_SCRIPT), f"Expect script not found at {EXPECT_SCRIPT}"
    with open(EXPECT_SCRIPT, "r") as f:
        content = f.read()

    # Retain the original script-content assertions.
    assert "spawn" in content, "Expect script does not use 'spawn'"
    assert "git push" in content, "Expect script does not contain 'git push'"
    assert "/home/user/alerts.git" in content, "Expect script does not push to the correct bare repository"
    assert "HEAD:main" in content, "Expect script does not push HEAD:main"
    assert "eof" in content.lower(), "Expect script does not wait for EOF"

    token = secrets.token_hex(10)
    filename = f"expect-verification-{token}.txt"
    commit_script = (
        f"printf '%s\\n' '{token}' > '{filename}' && "
        f"git add -- '{filename}' && git commit -m 'Expect verification {token}'"
    )
    commit = run_as_user(
        ["/bin/sh", "-c", commit_script],
        cwd=DUMMY_REPO,
        text=True,
        capture_output=True,
    )
    assert commit.returncode == 0, f"Could not prepare test commit: {commit.stderr}"
    expected_head = run_as_user(
        ["git", "rev-parse", "HEAD"], cwd=DUMMY_REPO,
        text=True, capture_output=True, check=True,
    ).stdout.strip()

    old_main_result = run_as_user(
        ["git", "--git-dir", BARE_REPO, "rev-parse", "--verify", "refs/heads/main"],
        text=True, capture_output=True,
    )
    old_main = old_main_result.stdout.strip() if old_main_result.returncode == 0 else None

    log_existed = os.path.exists(LOG_PATH)
    old_log = open(LOG_PATH, "rb").read() if log_existed else None
    marker = ("expect-marker-" + secrets.token_hex(8) + "\n").encode()

    try:
        run_as_user(
            ["git", "--git-dir", BARE_REPO, "update-ref", "-d", "refs/heads/main"],
            text=True, capture_output=True, check=True,
        )
        with open(LOG_PATH, "wb") as f:
            f.write(marker)
        user_info = pwd.getpwnam("user")
        os.chown(LOG_PATH, user_info.pw_uid, user_info.pw_gid)

        process = run_as_user(
            ["/usr/bin/expect", "-d", EXPECT_SCRIPT],
            cwd="/tmp",
            text=True,
            capture_output=True,
            timeout=30,
        )
        debug_output = process.stdout + "\n" + process.stderr
        assert process.returncode == 0, (
            f"Expect script failed: stdout={process.stdout!r}, stderr={process.stderr!r}"
        )
        assert "spawn: returns" in debug_output, "Expect script did not execute a spawn command"
        assert re.search(
            r"(?mi)^spawn\s+(?:/usr/bin/|/bin/)?(?:ba)?sh(?:\s|$)", debug_output
        ), "Expect script did not spawn a shell"

        remote_head = run_as_user(
            ["git", "--git-dir", BARE_REPO, "rev-parse", "refs/heads/main"],
            text=True, capture_output=True, check=True,
        ).stdout.strip()
        assert remote_head == expected_head, (
            "Running the Expect script did not push dummy_repo HEAD to refs/heads/main"
        )

        expected_log = marker + f"[MONITOR] refs/heads/main updated\n".encode()
        with open(LOG_PATH, "rb") as f:
            actual_log = f.read()
        assert actual_log == expected_log, (
            "The real push did not invoke the hook with the exact required result"
        )
    finally:
        if old_main:
            run_as_user(
                ["git", "--git-dir", BARE_REPO, "update-ref", "refs/heads/main", old_main],
                text=True, capture_output=True,
            )
        else:
            run_as_user(
                ["git", "--git-dir", BARE_REPO, "update-ref", "-d", "refs/heads/main"],
                text=True, capture_output=True,
            )
        if log_existed:
            with open(LOG_PATH, "wb") as f:
                f.write(old_log)
        elif os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)


def test_cron_job():
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"], capture_output=True, text=True, check=True
        )
        cron_output = result.stdout
    except subprocess.CalledProcessError:
        try:
            result = subprocess.run(
                ["crontab", "-l"], capture_output=True, text=True, check=True
            )
            cron_output = result.stdout
        except subprocess.CalledProcessError:
            pytest.fail("Failed to retrieve crontab. Is it set up?")

    assert "/usr/bin/expect" in cron_output, "Cron job does not call /usr/bin/expect"
    assert "/home/user/push_test.exp" in cron_output, "Cron job does not execute the expect script"

    lines = cron_output.strip().split("\n")
    found_cron = False
    for line in lines:
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split()
        if len(parts) >= 5:
            schedule = " ".join(parts[:5])
            if schedule == "* * * * *" and "/home/user/push_test.exp" in line:
                found_cron = True
                break
    assert found_cron, (
        "Could not find a cron job scheduled to run every minute (* * * * *) for the Expect script"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
