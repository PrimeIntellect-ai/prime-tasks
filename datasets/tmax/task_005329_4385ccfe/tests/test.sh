#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import signal
import subprocess
import time
from pathlib import Path

import pytest

EXPECTED = b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{"status":"healthy","service":"auth-service"}\n'
EXPECTED_BODY = '{"status":"healthy","service":"auth-service"}'


def run_checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {args}\nstdout={result.stdout!r}\nstderr={result.stderr!r}"
    )
    return result


def listening_owners(port):
    """Return {pid: cmdline} for every process owning a TCP listener on port."""
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            rows = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) >= 10:
                local_port = fields[1].rsplit(":", 1)[-1].upper()
                state = fields[3]
                if local_port == wanted and state == "0A":
                    inodes.add(fields[9])

    owners = {}
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    raw = (proc / "cmdline").read_bytes()
                    owners[int(proc.name)] = [
                        part.decode(errors="replace") for part in raw.split(b"\0") if part
                    ]
                    break
        except (OSError, PermissionError, ProcessLookupError):
            continue
    return owners


def process_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def test_auth_svc_binary():
    """Test the C source, compiled binary, and exact output."""
    c_file = "/home/user/auth_svc.c"
    bin_file = "/home/user/auth_svc"

    assert os.path.isfile(c_file), f"{c_file} does not exist."
    assert os.path.isfile(bin_file), f"{bin_file} does not exist."
    assert os.access(bin_file, os.X_OK), f"{bin_file} is not executable."
    assert Path(bin_file).read_bytes()[:4] == b"\x7fELF", "auth_svc is not a compiled ELF executable."

    result = subprocess.run([bin_file], capture_output=True, text=False)
    assert result.returncode == 0, "auth_svc execution failed."
    assert result.stdout == EXPECTED, "auth_svc output does not match the exact expected HTTP response."

    # Ensure the supplied C source itself builds and has the required behavior.
    rebuilt = "/tmp/auth_svc_rebuilt"
    run_checked(["gcc", c_file, "-o", rebuilt])
    rebuilt_result = subprocess.run([rebuilt], capture_output=True)
    assert rebuilt_result.returncode == 0
    assert rebuilt_result.stdout == EXPECTED, "Rebuilding auth_svc.c does not produce the required service."


def test_tls_configuration():
    """Test the certificate, socat TLS listener, and response."""
    crt_file = "/home/user/server.crt"
    key_file = "/home/user/server.key"

    assert os.path.isfile(crt_file), f"{crt_file} does not exist."
    assert os.path.isfile(key_file), f"{key_file} does not exist."

    key_info = run_checked(["openssl", "pkey", "-in", key_file, "-text", "-noout"], text=True)
    assert "2048 bit" in key_info.stdout and "Private-Key" in key_info.stdout, "server.key is not an RSA 2048-bit private key."
    cert_info = run_checked(["openssl", "x509", "-in", crt_file, "-text", "-noout"], text=True)
    assert "Public Key Algorithm: rsaEncryption" in cert_info.stdout
    assert "Public-Key: (2048 bit)" in cert_info.stdout
    run_checked(["openssl", "verify", "-CAfile", crt_file, crt_file], text=True)

    key_pub = run_checked(["openssl", "pkey", "-in", key_file, "-pubout"], text=False).stdout
    cert_pub = run_checked(["openssl", "x509", "-in", crt_file, "-pubkey", "-noout"], text=False).stdout
    assert key_pub == cert_pub, "server.crt does not match server.key."

    owners = listening_owners(8443)
    assert owners, "No process is listening on TCP port 8443."
    for pid, args in owners.items():
        assert os.path.basename(process_exe(pid)) == "socat", f"Port 8443 is owned by a non-socat process: {args}"
        joined = " ".join(args)
        assert re.search(r"OPENSSL-LISTEN:8443(?:,|\s|$)", joined, re.I), f"socat is not configured as an OPENSSL listener: {joined}"
        assert re.search(r"EXEC(?::|=)[^ ]*/home/user/auth_svc", joined), f"socat does not execute /home/user/auth_svc: {joined}"

    try:
        result = subprocess.run(
            ["curl", "-s", "-k", "https://localhost:8443"],
            capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, "curl to https://localhost:8443 failed."
        assert EXPECTED_BODY in result.stdout, "Unexpected response from TLS server."
    except subprocess.TimeoutExpired:
        pytest.fail("Timeout while trying to connect to TLS server on port 8443.")


def test_ssh_tunneling():
    """Test the real SSH keypair, authorization, and SSH-owned forwarding listener."""
    ssh_dir = "/home/user/.ssh"
    priv_key = os.path.join(ssh_dir, "id_ed25519")
    pub_key = os.path.join(ssh_dir, "id_ed25519.pub")
    auth_keys = os.path.join(ssh_dir, "authorized_keys")

    assert os.path.isfile(priv_key), f"{priv_key} does not exist."
    assert os.path.isfile(pub_key), f"{pub_key} does not exist."
    assert os.path.isfile(auth_keys), f"{auth_keys} does not exist."

    pub_key_content = Path(pub_key).read_text().strip()
    auth_keys_content = Path(auth_keys).read_text()
    assert pub_key_content in auth_keys_content, "Public key is not in authorized_keys."
    assert pub_key_content.startswith("ssh-ed25519 "), "Public key is not ed25519."

    derived = run_checked(["ssh-keygen", "-y", "-f", priv_key], text=True).stdout.strip().split()
    supplied = pub_key_content.split()
    assert len(derived) >= 2 and supplied[:2] == derived[:2], "SSH public and private keys do not match."
    authorized_pairs = [line.split()[:2] for line in auth_keys_content.splitlines() if len(line.split()) >= 2]
    assert supplied[:2] in authorized_pairs, "The generated key is not actually authorized."

    owners = listening_owners(9090)
    assert owners, "No process is listening on TCP port 9090."
    for pid, args in owners.items():
        assert os.path.basename(process_exe(pid)) == "ssh", f"Port 9090 is not owned by an SSH client: {args}"
        forward_args = [arg[2:] if arg.startswith("-L") else arg for arg in args]
        assert any(
            re.search(r"(?:^|:)9090:(?:localhost|127\.0\.0\.1|\[::1\]):8443$", arg)
            for arg in forward_args
        ), f"SSH listener does not forward port 9090 to localhost:8443: {args}"

    try:
        result = subprocess.run(
            ["curl", "-s", "-k", "https://localhost:9090"],
            capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, "curl to https://localhost:9090 failed."
        assert EXPECTED_BODY in result.stdout, "Unexpected response from SSH tunnel."
    except subprocess.TimeoutExpired:
        pytest.fail("Timeout while trying to connect to SSH tunnel on port 9090.")


def stop_existing_monitors():
    victims = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            args = [x for x in (proc / "cmdline").read_bytes().split(b"\0") if x]
            if any(x.decode(errors="ignore") == "/home/user/monitor.sh" for x in args):
                victims.append(int(proc.name))
        except OSError:
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_monitoring_daemon():
    """Check existing logs, then execute monitor.sh against a nonce response."""
    script_file = "/home/user/monitor.sh"
    log_file = "/home/user/health_log.txt"
    binary = Path("/home/user/auth_svc")
    backup = Path("/home/user/auth_svc.verifier-backup")

    assert os.path.isfile(script_file), f"{script_file} does not exist."
    assert os.access(script_file, os.X_OK), f"{script_file} is not executable."
    first_line = Path(script_file).read_text(errors="replace").splitlines()[0]
    assert first_line.startswith("#!") and "bash" in first_line, "monitor.sh is not a bash script."
    assert os.path.isfile(log_file), f"{log_file} does not exist."

    original_log = Path(log_file).read_bytes()
    lines = original_log.decode().strip().splitlines()
    assert len(lines) >= 3, f"Expected at least 3 lines in {log_file}, found {len(lines)}."
    for i, line in enumerate(lines):
        assert line == EXPECTED_BODY, f"Line {i+1} in {log_file} does not match expected JSON. Got: {line}"

    stop_existing_monitors()
    nonce = secrets.token_hex(16)
    challenge_line = json.dumps({"nonce": nonce}, separators=(",", ":"))
    replacement = (
        "#!/bin/sh\n"
        "printf '%s\\r\\n' 'HTTP/1.1 200 OK' 'Content-Type: application/json' ''\n"
        f"printf '%s\\n' '{challenge_line}'\n"
    ).encode()

    proc = None
    arrivals = []
    last_count = 0
    try:
        if backup.exists():
            backup.unlink()
        binary.rename(backup)
        binary.write_bytes(replacement)
        binary.chmod(0o755)
        Path(log_file).write_text("")
        os.chmod(log_file, 0o666)

        proc = subprocess.Popen(
            [script_file], cwd="/home/user", stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        )
        start = time.monotonic()
        deadline = start + 6.7
        while time.monotonic() < deadline:
            assert proc.poll() is None, "monitor.sh exited instead of running as a daemon."
            current = Path(log_file).read_text(errors="replace").splitlines()
            if len(current) > last_count:
                now = time.monotonic()
                arrivals.extend([now] * (len(current) - last_count))
                last_count = len(current)
            time.sleep(0.1)

        produced = Path(log_file).read_text(errors="replace").splitlines()
        assert 3 <= len(produced) <= 5, f"monitor.sh should log approximately every 2 seconds; produced {len(produced)} lines in 6.7 seconds."
        assert all(line == challenge_line for line in produced), (
            "monitor.sh did not fetch and extract only the dynamically supplied JSON body."
        )
        assert len(arrivals) >= 3 and arrivals[2] - arrivals[0] >= 3.0, "monitor.sh is not waiting approximately 2 seconds between checks."
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        if backup.exists():
            try:
                binary.unlink()
            except FileNotFoundError:
                pass
            backup.rename(binary)
        Path(log_file).write_bytes(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
