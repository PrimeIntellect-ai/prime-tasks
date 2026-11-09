#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile


def test_crack_token_go_exists():
    """Verify that the Go script was created at the specified path."""
    script_path = "/home/user/crack_token.go"
    assert os.path.isfile(script_path), f"Expected Go script at {script_path} does not exist."


def test_valid_auth_log_exists():
    """Verify that the valid_auth.log file exists."""
    log_path = "/home/user/valid_auth.log"
    assert os.path.isfile(log_path), f"Expected log file at {log_path} does not exist."


def test_valid_auth_log_content():
    """Verify that the content of valid_auth.log is exactly 'admin:secret73'."""
    log_path = "/home/user/valid_auth.log"
    assert os.path.isfile(log_path), "Log file does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "admin:secret73", f"Expected content 'admin:secret73', but got '{content}'."


def test_valid_auth_log_permissions():
    """Verify that the permissions of valid_auth.log are exactly 0600."""
    log_path = "/home/user/valid_auth.log"
    assert os.path.isfile(log_path), "Log file does not exist."

    file_stat = os.stat(log_path)
    permissions = stat.S_IMODE(file_stat.st_mode)

    assert permissions == 0o600, f"Expected permissions 0600, but got {oct(permissions)}."


def _remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.islink(path) or not os.path.isdir(path):
        os.unlink(path)
    else:
        shutil.rmtree(path)


def test_z_go_script_cracks_derived_token_sets():
    """Run the submitted Go program against fresh token sets with derived answers."""
    script_path = "/home/user/crack_token.go"
    token_dir = "/home/user/intercepted_tokens"
    log_path = "/home/user/valid_auth.log"

    user_stat = os.stat("/home/user")
    uid, gid = user_stat.st_uid, user_stat.st_gid

    backup_root = tempfile.mkdtemp(prefix="token-verifier-")
    backup_tokens = os.path.join(backup_root, "intercepted_tokens")
    os.rename(token_dir, backup_tokens)

    log_stat = os.stat(log_path)
    with open(log_path, "rb") as f:
        saved_log = f.read()

    cache_dir = "/tmp/go-cache-token-verifier"
    _remove_path(cache_dir)
    os.mkdir(cache_dir, 0o700)
    os.chown(cache_dir, uid, gid)

    try:
        previous_n = None
        for trial in range(2):
            n = secrets.randbelow(101)
            while n == 73 or n == previous_n:
                n = secrets.randbelow(101)
            previous_n = n
            expected = f"admin:secret{n}"

            _remove_path(token_dir)
            os.mkdir(token_dir, 0o755)
            os.chown(token_dir, uid, gid)

            # Keep the original token naming convention, but ensure the valid
            # token is not in the original hardcoded token_4 location.
            target_position = secrets.choice((1, 2, 3, 5))
            nonce = secrets.token_hex(16)
            for position in range(1, 6):
                if position == target_position:
                    digest = hashlib.md5(expected.encode()).hexdigest()
                else:
                    digest = hashlib.md5(
                        f"verifier-decoy-{trial}-{position}-{nonce}".encode()
                    ).hexdigest()
                path = os.path.join(token_dir, f"token_{position}.txt")
                with open(path, "w") as f:
                    f.write(digest + "\n")
                os.chown(path, uid, gid)
                os.chmod(path, 0o644)

            _remove_path(log_path)
            env = os.environ.copy()
            env.update({
                "HOME": "/home/user",
                "GOCACHE": cache_dir,
                "GO111MODULE": "off",
            })
            result = subprocess.run(
                ["runuser", "-u", "user", "--", "go", "run", script_path],
                cwd="/home/user",
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60,
            )
            assert result.returncode == 0, (
                f"Go script failed on generated token set (exit {result.returncode}).\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

            evidence = result.stdout + "\n" + result.stderr
            if os.path.isfile(log_path):
                with open(log_path, "r", errors="replace") as f:
                    evidence += "\n" + f.read()

            recovered = set(re.findall(r"admin:secret(?:100|[0-9]{1,2})(?![0-9])", evidence))
            assert recovered == {expected}, (
                f"Go script did not uniquely identify the generated matching plaintext. "
                f"Expected {expected!r}, recovered {sorted(recovered)!r}."
            )
    finally:
        _remove_path(token_dir)
        os.rename(backup_tokens, token_dir)
        shutil.rmtree(backup_root, ignore_errors=True)
        _remove_path(log_path)
        with open(log_path, "wb") as f:
            f.write(saved_log)
        os.chown(log_path, log_stat.st_uid, log_stat.st_gid)
        os.chmod(log_path, stat.S_IMODE(log_stat.st_mode))
        _remove_path(cache_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
