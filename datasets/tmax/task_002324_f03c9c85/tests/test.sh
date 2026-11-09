#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import socket
import string
import subprocess
import tempfile
import urllib.error
import urllib.request


def test_run_sanitizer_env_vars():
    script_path = "/home/user/run_sanitizer.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "LANG=en_US.UTF-8" in content, "LANG=en_US.UTF-8 not exported in run_sanitizer.sh"
    assert "TZ=UTC" in content, "TZ=UTC not exported in run_sanitizer.sh"
    assert "BACKEND_PORT=9000" in content, "BACKEND_PORT=9000 not exported in run_sanitizer.sh"

    # Execute the wrapper with a temporary ./sanitizer probe to verify that it
    # actually invokes the binary and supplies the required environment.
    sanitizer_path = "/home/user/sanitizer"
    backup_path = f"/home/user/.sanitizer.verifier-backup-{secrets.token_hex(8)}"
    output_path = f"/tmp/wrapper-probe-{secrets.token_hex(8)}"
    probe_arg = f"/tmp/input-{secrets.token_hex(12)}"
    assert os.path.isfile(sanitizer_path), f"Compiled binary {sanitizer_path} not found."

    os.rename(sanitizer_path, backup_path)
    try:
        with open(sanitizer_path, "w") as probe:
            probe.write("#!/bin/sh\n")
            probe.write(f"printf '%s\\n' \"$LANG\" \"$TZ\" \"$BACKEND_PORT\" \"$1\" > {output_path!r}\n")
        os.chmod(sanitizer_path, 0o755)

        env = os.environ.copy()
        env.update({"LANG": "wrong_LANG", "TZ": "wrong_TZ", "BACKEND_PORT": "1"})
        result = subprocess.run(
            [script_path, probe_arg], cwd="/home/user", env=env,
            capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, f"run_sanitizer.sh failed to execute ./sanitizer: {result.stderr}"
        assert os.path.isfile(output_path), "run_sanitizer.sh did not execute the ./sanitizer binary"
        with open(output_path, "r") as f:
            values = f.read().splitlines()
        assert values == ["en_US.UTF-8", "UTC", "9000", probe_arg], \
            f"Wrapper supplied incorrect environment or argument: {values!r}"
    finally:
        try:
            os.unlink(sanitizer_path)
        except FileNotFoundError:
            pass
        os.rename(backup_path, sanitizer_path)
        try:
            os.unlink(output_path)
        except FileNotFoundError:
            pass


def _proc_tcp_entries():
    entries = {}
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10:
                continue
            local_port = int(fields[1].rsplit(":", 1)[1], 16)
            remote_port = int(fields[2].rsplit(":", 1)[1], 16)
            state = fields[3]
            inode = fields[9]
            entries[inode] = (local_port, remote_port, state)
    return entries


def _ssh_owns_tunnel():
    entries = _proc_tcp_entries()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            exe = os.path.basename(os.path.realpath(f"/proc/{pid}/exe"))
            if exe != "ssh":
                continue
            owned = set()
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    target = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target.endswith("]"):
                    owned.add(target[8:-1])
            sockets = [entries[i] for i in owned if i in entries]
            listens_9000 = any(local == 9000 and state == "0A" for local, remote, state in sockets)
            connected_2222 = any(
                state == "01" and (local == 2222 or remote == 2222)
                for local, remote, state in sockets
            )
            if listens_9000 and connected_2222:
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return False


def test_ssh_tunnel_active():
    try:
        req = urllib.request.urlopen("http://127.0.0.1:9000/ping", timeout=5)
        status = req.getcode()
        assert status == 200, f"Expected HTTP 200 OK from backend, got {status}"
    except urllib.error.URLError as e:
        assert False, f"Failed to reach backend via SSH tunnel on port 9000: {e}"
    except Exception as e:
        assert False, f"Unexpected error checking SSH tunnel: {e}"

    assert _ssh_owns_tunnel(), \
        "Port 9000 is not owned by an SSH client connected to the VM SSH port 2222"


def _assert_classification(binary, filepath, rejected):
    result = subprocess.run([binary, filepath], capture_output=True, timeout=10)
    expected_code = 1 if rejected else 0
    expected_text = b"REJECTED" if rejected else b"ACCEPTED"
    assert result.returncode == expected_code, \
        f"{binary} returned {result.returncode} for generated input; expected {expected_code}"
    assert expected_text in result.stdout, \
        f"{binary} did not print {expected_text.decode()} for generated input: {result.stdout!r}"


def test_generated_secret_corpus_and_source():
    source_path = "/home/user/sanitizer.c"
    installed_binary = "/home/user/sanitizer"
    assert os.path.isfile(source_path), f"Source file {source_path} not found."
    assert os.path.isfile(installed_binary), f"Compiled binary {installed_binary} not found."
    assert os.access(installed_binary, os.X_OK), f"{installed_binary} is not executable."
    with open(installed_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{installed_binary} is not a compiled ELF binary"

    with tempfile.TemporaryDirectory(prefix="sanitizer-secret-") as tempdir:
        rebuilt = os.path.join(tempdir, "rebuilt-sanitizer")
        compile_result = subprocess.run(
            ["gcc", source_path, "-o", rebuilt], capture_output=True, text=True, timeout=20
        )
        assert compile_result.returncode == 0, \
            f"Failed to compile {source_path}: {compile_result.stderr}"

        alphabet = string.ascii_letters + string.digits + " _-./"
        safe = "".join(secrets.choice(alphabet) for _ in range(257)).encode()
        cases = [
            (b"", False),
            (safe, False),
            (b"EVIL_PAYLOA", False),
            (b"XEVIL_PAYLOADY", True),
            (safe[:80] + b"`" + safe[80:], True),
            (b"prefix EVIL_PAYLOAD suffix", True),
            (b"A" * 8190 + b"EVIL_PAYLOAD" + b"B" * 8190, True),
            (b"A" * 8192 + b"`" + b"B" * 8192, True),
            (b"EVIL_PAYLO" + b"AD", True),
        ]

        for index, (payload, rejected) in enumerate(cases):
            name = secrets.token_hex(12) + f"-{index}.dat"
            path = os.path.join(tempdir, name)
            with open(path, "wb") as f:
                f.write(payload)
            for binary in (installed_binary, rebuilt):
                _assert_classification(binary, path, rejected)


def test_adversarial_corpus():
    sanitizer_bin = "/home/user/sanitizer"
    assert os.path.isfile(sanitizer_bin), f"Compiled binary {sanitizer_bin} not found."
    assert os.access(sanitizer_bin, os.X_OK), f"{sanitizer_bin} is not executable."

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_rejected = []

    for f in evil_files:
        filepath = os.path.join(evil_dir, f)
        result = subprocess.run([sanitizer_bin, filepath], capture_output=True, text=True)
        if result.returncode != 1 or "REJECTED" not in result.stdout:
            evil_bypassed.append(f)

    for f in clean_files:
        filepath = os.path.join(clean_dir, f)
        result = subprocess.run([sanitizer_bin, filepath], capture_output=True, text=True)
        if result.returncode != 0 or "ACCEPTED" not in result.stdout:
            clean_rejected.append(f)

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")

    assert not evil_bypassed and not clean_rejected, " | ".join(error_messages)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
