#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import time
from pathlib import Path

SCRIPT_PATH = "/home/user/fix_site.py"
CONF_PATH = "/home/user/nginx/conf/alice.conf"
HOOK_PATH = "/home/user/git/alice.git/hooks/pre-receive"
APPS_DIR = "/home/user/apps/alice"
FLAG_PATH = "/home/user/alice_unlocked.flag"
ADMIN_TOOL = "/home/user/scripts/admin_tool.py"
INVOCATION_MARKER = f"/tmp/admin_tool_success_{secrets.token_hex(16)}"


def _clear_apps_dir():
    shutil.rmtree(APPS_DIR, ignore_errors=True)
    os.makedirs(APPS_DIR, exist_ok=True)


def _run_hook():
    return subprocess.run(
        [HOOK_PATH], input="", capture_output=True, text=True, timeout=10
    )


def test_00_fix_site_script_executes_and_is_idempotent():
    assert os.path.isfile(SCRIPT_PATH), f"Automation script missing: {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "Automation script must be a real file, not a symlink."

    with open(SCRIPT_PATH, "rb") as f:
        source = f.read()
    assert source.strip(), "Automation script is empty."
    compile(source, SCRIPT_PATH, "exec")

    os.makedirs(os.path.dirname(CONF_PATH), exist_ok=True)
    with open(CONF_PATH, "w") as f:
        f.write("""server {
    listen 8080;
    server_name alice.example.com;

    location / {
        proxy_pass http://unix:/tmp/wrong.sock;
        proxy_set_header Host $host;
    }
}
""")

    os.makedirs(os.path.dirname(HOOK_PATH), exist_ok=True)
    if os.path.lexists(HOOK_PATH):
        os.remove(HOOK_PATH)
    for path in (FLAG_PATH, INVOCATION_MARKER):
        if os.path.lexists(path):
            os.remove(path)
    _clear_apps_dir()

    # Restore the specified interactive tool and add a private success marker so
    # verification can establish that fix_site.py actually completed its flow.
    os.makedirs(os.path.dirname(ADMIN_TOOL), exist_ok=True)
    admin_source = f'''#!/usr/bin/env python3
import sys

if len(sys.argv) != 3 or sys.argv[1] != "unlock":
    print("Usage: admin_tool.py unlock <user>")
    sys.exit(1)

user = sys.argv[2]
pwd = input("Admin Password: ")
if pwd != "supersecret99":
    print("Auth failed")
    sys.exit(1)

conf = input(f"Confirm unlock for {{user}}? (y/n): ")
if conf.lower().strip() == "y":
    with open(f"/home/user/{{user}}_unlocked.flag", "w") as f:
        f.write("UNLOCKED\\n")
    with open({INVOCATION_MARKER!r}, "w") as f:
        f.write(user + "\\n")
    print("Success")
    sys.exit(0)

print("Cancelled")
sys.exit(1)
'''
    with open(ADMIN_TOOL, "w") as f:
        f.write(admin_source)
    os.chmod(ADMIN_TOOL, 0o755)

    first = subprocess.run(
        ["python3", SCRIPT_PATH], capture_output=True, text=True, timeout=30
    )
    assert first.returncode == 0, (
        f"fix_site.py failed on first execution: stdout={first.stdout!r}, "
        f"stderr={first.stderr!r}"
    )
    assert os.path.isfile(INVOCATION_MARKER), (
        "fix_site.py did not successfully run the interactive admin tool."
    )
    assert Path(INVOCATION_MARKER).read_text() == "alice\n"

    with open(CONF_PATH, "rb") as f:
        first_conf = f.read()
    first_conf_mtime = os.stat(CONF_PATH).st_mtime_ns

    # Force the second execution to perform the interactive unlock again while
    # checking that the already-correct Nginx file is not rewritten.
    os.remove(INVOCATION_MARKER)
    if os.path.exists(FLAG_PATH):
        os.remove(FLAG_PATH)
    time.sleep(0.05)

    second = subprocess.run(
        ["python3", SCRIPT_PATH], capture_output=True, text=True, timeout=30
    )
    assert second.returncode == 0, (
        f"fix_site.py failed on second execution: stdout={second.stdout!r}, "
        f"stderr={second.stderr!r}"
    )
    assert os.path.isfile(INVOCATION_MARKER), (
        "fix_site.py did not successfully run the interactive admin tool on rerun."
    )
    with open(CONF_PATH, "rb") as f:
        second_conf = f.read()
    assert second_conf == first_conf, "Nginx configuration changed on an idempotent rerun."
    assert os.stat(CONF_PATH).st_mtime_ns == first_conf_mtime, (
        "fix_site.py rewrote the already-correct Nginx configuration."
    )


def test_nginx_conf_fixed():
    conf_path = "/home/user/nginx/conf/alice.conf"
    assert os.path.isfile(conf_path), f"Nginx config missing: {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    expected_proxy = "http://unix:/home/user/apps/alice/app.sock"
    assert expected_proxy in content, f"Nginx config does not contain the correct proxy_pass: {expected_proxy}"
    assert "/tmp/wrong.sock" not in content, "Nginx config still contains the old wrong socket path."


def test_pre_receive_hook_exists_and_executable():
    hook_path = "/home/user/git/alice.git/hooks/pre-receive"
    assert os.path.isfile(hook_path), f"Git hook missing: {hook_path}"
    assert os.access(hook_path, os.X_OK), f"Git hook is not executable: {hook_path}"


def test_pre_receive_hook_logic():
    hook_path = "/home/user/git/alice.git/hooks/pre-receive"
    apps_dir = "/home/user/apps/alice"
    dummy_file = os.path.join(apps_dir, "dummy_large_file.bin")

    os.makedirs(apps_dir, exist_ok=True)

    try:
        with open(dummy_file, "wb") as f:
            f.seek((51 * 1024 * 1024) - 1)
            f.write(b"\0")

        result_exceeded = subprocess.run([hook_path], capture_output=True, text=True)

        assert result_exceeded.returncode == 1, "Hook should exit with code 1 when quota is exceeded."
        assert result_exceeded.stdout.strip() == "Error: Quota exceeded", "Hook output did not match exactly 'Error: Quota exceeded'."

        os.remove(dummy_file)

        result_ok = subprocess.run([hook_path], capture_output=True, text=True)

        assert result_ok.returncode == 0, "Hook should exit with code 0 when within quota."

    finally:
        if os.path.exists(dummy_file):
            os.remove(dummy_file)


def test_pre_receive_hook_sums_random_nested_files_at_exact_boundary():
    _clear_apps_dir()
    token = secrets.token_hex(12)
    nested = os.path.join(APPS_DIR, f"dir_{token}", f"nested_{secrets.token_hex(6)}")
    os.makedirs(nested)

    # Randomized names and partitions prevent special-casing the public fixture.
    first_size = 1_000_000 + secrets.randbelow(15_000_000)
    second_size = 1_000_000 + secrets.randbelow(15_000_000)
    third_size = 50_000_000 - first_size - second_size
    assert third_size > 0

    paths = [
        os.path.join(APPS_DIR, f"a_{secrets.token_hex(8)}.dat"),
        os.path.join(nested, f"b_{secrets.token_hex(8)}.blob"),
        os.path.join(nested, f"c_{secrets.token_hex(8)}.payload"),
    ]

    try:
        for path, size in zip(paths, (first_size, second_size, third_size)):
            with open(path, "wb") as f:
                f.truncate(size)

        at_limit = _run_hook()
        assert at_limit.returncode == 0, (
            "Hook must allow a total size of exactly 50,000,000 bytes."
        )

        with open(paths[1], "ab") as f:
            f.write(b"X")

        over_limit = _run_hook()
        assert over_limit.returncode == 1, (
            "Hook must reject a randomized nested-file total of 50,000,001 bytes."
        )
        assert over_limit.stdout.strip() == "Error: Quota exceeded", (
            "Hook output did not match exactly 'Error: Quota exceeded'."
        )
    finally:
        _clear_apps_dir()


def test_admin_tool_flag():
    flag_path = "/home/user/alice_unlocked.flag"
    assert os.path.isfile(flag_path), f"Flag file missing: {flag_path}. The admin tool was likely not run successfully."

    with open(flag_path, "r") as f:
        content = f.read()

    assert content == "UNLOCKED\n", f"Flag file content is incorrect: {repr(content)}"


def test_fix_site_script_exists():
    script_path = "/home/user/fix_site.py"
    assert os.path.isfile(script_path), f"Automation script missing: {script_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
