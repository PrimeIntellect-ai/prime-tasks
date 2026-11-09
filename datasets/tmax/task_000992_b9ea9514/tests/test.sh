#!/bin/bash
mkdir -p /logs/verifier

# Ensure the verifier controls the audit server used during execution.
pkill -f '/home/user/ws_server.py' 2>/dev/null || true

cat <<'PY_EOF' > /tmp/verify_updater.py
import json
import os
import secrets
import subprocess
import sys
import time
import traceback

HOME = "/home/user"
SOURCE = os.path.join(HOME, "updater.c")
BINARY = os.path.join(HOME, "updater")
POLICY = os.path.join(HOME, "policy.conf")
PATCH = os.path.join(HOME, "update.patch")
AUDIT = os.path.join(HOME, "audit_log.json")
SERVER = os.path.join(HOME, "ws_server.py")


def fletcher16(data):
    sum1 = 0
    sum2 = 0
    for byte in data:
        sum1 = (sum1 + byte) % 255
        sum2 = (sum2 + sum1) % 255
    return (sum2 << 8) | sum1


def write_file(path, data):
    with open(path, "wb") as f:
        f.write(data)


def wait_for_audit():
    deadline = time.time() + 5
    while time.time() < deadline:
        if os.path.isfile(AUDIT) and os.path.getsize(AUDIT) > 0:
            time.sleep(0.1)
            return
        time.sleep(0.05)
    raise AssertionError(
        f"The file {AUDIT} does not exist or is empty. "
        "Did the C program run and send the WebSocket message?"
    )


def run_case(executable, initial, patch, expected, fixed_checksums=None):
    write_file(POLICY, initial)
    write_file(PATCH, patch)
    try:
        os.remove(AUDIT)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [executable], cwd=HOME, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile(POLICY), f"{POLICY} is missing."
    with open(POLICY, "rb") as f:
        actual_policy = f.read()
    assert actual_policy == expected, (
        "policy.conf does not exactly match the result of applying update.patch.\n"
        f"Expected: {expected!r}\nActual:   {actual_policy!r}"
    )

    wait_for_audit()
    with open(AUDIT, "r", encoding="utf-8") as f:
        lines = [line for line in f.read().splitlines() if line != ""]
    assert len(lines) > 0 and lines[0] != "", f"The {AUDIT} file is empty."
    assert len(lines) == 1, f"Expected one WebSocket JSON message, got {len(lines)}."

    try:
        data = json.loads(lines[-1])
    except json.JSONDecodeError as exc:
        raise AssertionError(f"The last line of {AUDIT} is not valid JSON: {exc}")

    old_checksum = fletcher16(initial)
    new_checksum = fletcher16(expected)
    assert data.get("status") == "patched", (
        f"Expected status 'patched', got {data.get('status')}"
    )
    assert data.get("old_checksum") == old_checksum, (
        f"Expected old_checksum {old_checksum}, got {data.get('old_checksum')}"
    )
    assert data.get("new_checksum") == new_checksum, (
        f"Expected new_checksum {new_checksum}, got {data.get('new_checksum')}"
    )

    if fixed_checksums is not None:
        # Preserve the original verifier's canonical checksum assertions.
        assert data.get("old_checksum") == fixed_checksums[0], (
            f"Expected old_checksum {fixed_checksums[0]}, got {data.get('old_checksum')}"
        )
        assert data.get("new_checksum") == fixed_checksums[1], (
            f"Expected new_checksum {fixed_checksums[1]}, got {data.get('new_checksum')}"
        )

    return actual_policy


def dynamic_case():
    token = secrets.token_hex(12)
    old_port = 10000 + secrets.randbelow(20000)
    new_port = 30000 + secrets.randbelow(20000)
    old_limit = 20 + secrets.randbelow(200)
    new_limit = 300 + secrets.randbelow(500)
    old_admin = "root_" + token
    new_admin = "admin_" + token

    initial = (
        f"AllowPort {old_port}\n"
        f"PolicyToken {token}\n"
        f"MaxConns {old_limit}\n"
        f"AdminUser {old_admin}\n"
    ).encode()
    patch = (
        "--- policy.conf\n"
        "+++ policy.conf\n"
        "@@ -1,4 +1,5 @@\n"
        f" AllowPort {old_port}\n"
        f"+AllowPort {new_port}\n"
        f" PolicyToken {token}\n"
        f"-MaxConns {old_limit}\n"
        f"+MaxConns {new_limit}\n"
        f"-AdminUser {old_admin}\n"
        f"+AdminUser {new_admin}\n"
    ).encode()
    expected = (
        f"AllowPort {old_port}\n"
        f"AllowPort {new_port}\n"
        f"PolicyToken {token}\n"
        f"MaxConns {new_limit}\n"
        f"AdminUser {new_admin}\n"
    ).encode()
    return initial, patch, expected


def main():
    # Preserve the original source and executable checks.
    assert os.path.isfile(SOURCE), f"The C source file {SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"The compiled binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"The file {BINARY} is not executable."
    assert os.path.isfile(SERVER), f"The provided audit server {SERVER} is missing."

    server = subprocess.Popen(
        [sys.executable, SERVER], cwd=HOME,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        for _ in range(30):
            if server.poll() is not None:
                raise AssertionError("The provided WebSocket audit server failed to start.")
            time.sleep(0.1)
            if server.poll() is None:
                # A short startup delay is sufficient before websocat connects.
                if _ >= 4:
                    break

        canonical_initial = b"AllowPort 80\nMaxConns 10\nAdminUser root\n"
        canonical_patch = (
            b"--- policy.conf\n"
            b"+++ policy.conf\n"
            b"@@ -1,3 +1,4 @@\n"
            b" AllowPort 80\n"
            b"+AllowPort 443\n"
            b" MaxConns 10\n"
            b"-AdminUser root\n"
            b"+AdminUser admin\n"
        )
        canonical_expected = (
            b"AllowPort 80\nAllowPort 443\nMaxConns 10\nAdminUser admin\n"
        )

        actual = run_case(
            BINARY, canonical_initial, canonical_patch, canonical_expected,
            fixed_checksums=(44864, 36816)
        )

        # Preserve the original policy-content assertions as well as requiring
        # an exact patched result.
        content = actual.decode()
        assert "AllowPort 80" in content, "policy.conf is missing 'AllowPort 80'"
        assert "AllowPort 443" in content, (
            "policy.conf is missing 'AllowPort 443' (patch not applied correctly)"
        )
        assert "AdminUser admin" in content, (
            "policy.conf is missing 'AdminUser admin' (patch not applied correctly)"
        )
        assert "AdminUser root" not in content, (
            "policy.conf still contains 'AdminUser root' (patch not applied correctly)"
        )

        # Exercise the submitted binary on an unpredictable policy and patch so
        # fixed checksums or direct edits of the canonical file cannot pass.
        initial, patch, expected = dynamic_case()
        run_case(BINARY, initial, patch, expected)

        # Compile and exercise updater.c itself, tying the required source to the
        # behavior rather than trusting an unrelated prebuilt executable.
        rebuilt = "/tmp/updater_from_submitted_source"
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert compile_result.returncode == 0, (
            "updater.c failed to compile with gcc.\n"
            f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
        )
        initial, patch, expected = dynamic_case()
        run_case(rebuilt, initial, patch, expected)
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
PY_EOF

python3 /tmp/verify_updater.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
