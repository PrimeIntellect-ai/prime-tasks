#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

import pytest
import requests

PACKAGE = "/app/bash-web-auditor"
AUDITOR = "/home/user/bin/auditor.sh"
WORKER = "/home/user/bin/worker.sh"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, **kwargs)


def test_makefile_fixed_and_installed():
    makefile = os.path.join(PACKAGE, "Makefile")
    assert os.path.isfile(makefile), "Package Makefile is missing."
    with open(makefile, "r") as f:
        make_content = f.read()
    assert re.search(r"(?m)^install\s*:", make_content), "Makefile has no install target."
    assert "cp -z" not in make_content, "The broken cp -z typo is still present."

    # Actually exercise make install from a clean destination, then restore the
    # agent's installed files so this check does not overwrite later fixes.
    backup_root = tempfile.mkdtemp(prefix="verifier-bin-backup-")
    backup_bin = os.path.join(backup_root, "bin")
    if os.path.lexists("/home/user/bin"):
        shutil.copytree("/home/user/bin", backup_bin, symlinks=True)
    try:
        shutil.rmtree("/home/user/bin", ignore_errors=True)
        os.makedirs("/home/user/bin", exist_ok=True)
        result = subprocess.run(["make", "install"], cwd=PACKAGE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=15)
        assert result.returncode == 0, f"make install failed:\n{result.stdout}\n{result.stderr}"
        for name in ("auditor.sh", "worker.sh"):
            installed = os.path.join("/home/user/bin", name)
            source = os.path.join(PACKAGE, name)
            assert os.path.isfile(installed), f"make install did not install {name}."
            assert os.access(installed, os.X_OK), f"make install did not make {name} executable."
            with open(installed, "rb") as f:
                installed_data = f.read()
            with open(source, "rb") as f:
                source_data = f.read()
            assert installed_data == source_data, f"make install did not copy {name} from the package."
    finally:
        shutil.rmtree("/home/user/bin", ignore_errors=True)
        if os.path.exists(backup_bin):
            shutil.copytree(backup_bin, "/home/user/bin", symlinks=True)
        else:
            os.makedirs("/home/user/bin", exist_ok=True)
        shutil.rmtree(backup_root, ignore_errors=True)

    assert os.path.exists(AUDITOR), f"File {AUDITOR} is missing. Did you run make install?"
    assert os.path.exists(WORKER), f"File {WORKER} is missing. Did you run make install?"
    assert os.access(AUDITOR, os.X_OK), f"File {AUDITOR} is not executable."
    assert os.access(WORKER, os.X_OK), f"File {WORKER} is not executable."


def test_cwe_identification():
    cwe_path = "/app/cwe.txt"
    assert os.path.exists(cwe_path), f"File {cwe_path} is missing."
    with open(cwe_path, "r") as f:
        content = f.read().strip()
    assert "CWE-532" in content.upper(), f"Expected CWE-532 in {cwe_path}, got {content}"
    assert content.upper() == "CWE-532", f"{cwe_path} must contain the exact ID CWE-532."


def cert_text(path):
    return run(["openssl", "x509", "-in", path, "-noout", "-text"]).stdout


def public_key_bits_from_cert(path):
    pub = subprocess.run(["openssl", "x509", "-in", path, "-pubkey", "-noout"],
                         check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    parsed = subprocess.run(["openssl", "pkey", "-pubin", "-text", "-noout"],
                            input=pub.stdout, check=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    text = parsed.stdout.decode(errors="replace")
    match = re.search(r"Public-Key:\s*\((\d+) bit\)", text)
    assert match, f"Could not determine RSA key size for {path}."
    return int(match.group(1)), text


def test_certificates_exist_and_are_valid():
    for path in ("/app/ca.crt", "/app/server.crt", "/app/server.key"):
        assert os.path.isfile(path), f"Required certificate file {path} is missing."

    run(["openssl", "x509", "-in", "/app/ca.crt", "-noout"])
    run(["openssl", "x509", "-in", "/app/server.crt", "-noout"])
    run(["openssl", "pkey", "-in", "/app/server.key", "-check", "-noout"])

    ca_bits, ca_key_text = public_key_bits_from_cert("/app/ca.crt")
    server_bits, server_key_text = public_key_bits_from_cert("/app/server.crt")
    assert ca_bits == 2048 and "RSA" in ca_key_text.upper(), "Root CA must use a 2048-bit RSA key."
    assert server_bits == 2048 and "RSA" in server_key_text.upper(), "Server certificate must use a 2048-bit RSA key."

    key_details = run(["openssl", "pkey", "-in", "/app/server.key", "-text", "-noout"]).stdout
    key_match = re.search(r"Private-Key:\s*\((\d+) bit", key_details)
    assert key_match and int(key_match.group(1)) == 2048, "Server private key must be 2048-bit RSA."

    # Both certificates must still be valid for at least 30 days.
    for path in ("/app/ca.crt", "/app/server.crt"):
        result = subprocess.run(["openssl", "x509", "-in", path, "-checkend", str(30 * 86400), "-noout"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert result.returncode == 0, f"{path} is not valid for at least 30 more days."

    ca_text = cert_text("/app/ca.crt")
    assert re.search(r"CA:\s*TRUE", ca_text), "Root certificate is not marked as a CA."
    run(["openssl", "verify", "-CAfile", "/app/ca.crt", "/app/ca.crt"])
    run(["openssl", "verify", "-CAfile", "/app/ca.crt", "/app/server.crt"])
    run(["openssl", "x509", "-in", "/app/server.crt", "-noout", "-checkhost", "localhost"])

    cert_mod = run(["openssl", "x509", "-in", "/app/server.crt", "-noout", "-modulus"]).stdout.strip()
    key_mod = run(["openssl", "rsa", "-in", "/app/server.key", "-noout", "-modulus"]).stdout.strip()
    assert cert_mod == key_mod, "Server certificate and private key do not match."


def listener_processes():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            address, port = fields[1].rsplit(":", 1)
            if int(port, 16) != 8443:
                continue
            # For IPv4, require 127.0.0.1 rather than a wildcard listener.
            if table.endswith("tcp") and address.upper() != "0100007F":
                continue
            inodes.add(fields[9])

    owners = []
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = os.path.basename(proc_dir)
        fd_dir = os.path.join(proc_dir, "fd")
        try:
            links = [os.readlink(p) for p in glob.glob(fd_dir + "/*")]
        except OSError:
            continue
        if not any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
            continue
        try:
            with open(os.path.join(proc_dir, "cmdline"), "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace").strip()
            exe = os.readlink(os.path.join(proc_dir, "exe"))
        except OSError:
            continue
        owners.append((pid, exe, cmdline))
    return owners


def test_service_is_socat_ssl_exec():
    owners = listener_processes()
    assert owners, "No process is listening on 127.0.0.1:8443."
    socat = []
    for pid, exe, cmdline in owners:
        low = cmdline.lower()
        if os.path.basename(exe).startswith("socat") or re.search(r"(^|\s)socat(\s|$)", low):
            socat.append((pid, exe, cmdline))
    assert socat, f"The 8443 listener is not socat: {owners}"

    combined = "\n".join(item[2] for item in socat).lower()
    assert "openssl-listen:8443" in combined, "socat is not using an OPENSSL-LISTEN endpoint on port 8443."
    assert "cert=/app/server.crt" in combined, "socat is not configured with /app/server.crt."
    assert "key=/app/server.key" in combined, "socat is not configured with /app/server.key."
    assert "fork" in combined, "socat must execute a handler for each incoming connection."
    assert "/home/user/bin/auditor.sh" in combined, "socat does not execute the installed auditor.sh."
    assert "exec:" in combined or "system:" in combined, "socat is not configured to execute the auditor script."


def test_auditor_script_modifications():
    with open(AUDITOR, "r") as f:
        content = f.read()

    # Preserve the original static assertions.
    assert not re.search(r'worker\.sh\s+"?\$token"?', content), \
        "worker.sh is still being called with the token as a command-line argument."
    assert "SECRET_TOKEN" in content, "SECRET_TOKEN environment variable is not used in auditor.sh."


def test_https_service_redaction_and_worker_environment():
    capture_dir = "/tmp/verifier_worker_capture"
    shutil.rmtree(capture_dir, ignore_errors=True)
    os.makedirs(capture_dir, mode=0o777)

    with open(WORKER, "rb") as f:
        original_worker = f.read()
    original_mode = stat.S_IMODE(os.stat(WORKER).st_mode)

    mock_worker = b'''#!/bin/bash
umask 000
{
  printf '%s\\n' "$SECRET_TOKEN"
  printf '%s\\n' "$#"
  printf '%s\\n' "$*"
} > /tmp/verifier_worker_capture/capture.$$.txt
'''

    log_path = "/app/audit.log"
    old_size = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    tokens = ["verify_" + uuid.uuid4().hex, "second_" + uuid.uuid4().hex]

    try:
        with open(WORKER, "wb") as f:
            f.write(mock_worker)
        os.chmod(WORKER, 0o755)

        for token in tokens:
            response = requests.get(
                "https://127.0.0.1:8443/",
                headers={"Authorization": f"Bearer {token}"},
                verify="/app/ca.crt",
                timeout=5,
            )
            assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

        deadline = time.time() + 4
        captures = []
        while time.time() < deadline:
            captures = glob.glob(os.path.join(capture_dir, "capture.*.txt"))
            if len(captures) >= len(tokens):
                break
            time.sleep(0.1)

        assert len(captures) >= len(tokens), "auditor.sh did not invoke worker.sh for each request."
        captured = []
        for path in captures:
            with open(path, "r") as f:
                lines = f.read().splitlines()
            if len(lines) >= 3:
                captured.append((lines[0], lines[1], lines[2]))

        for token in tokens:
            matches = [entry for entry in captured if entry[0] == token]
            assert matches, f"Bearer token {token} was not forwarded in SECRET_TOKEN."
            assert any(entry[1] == "0" and entry[2] == "" for entry in matches), \
                "worker.sh received command-line arguments; the token must only be in SECRET_TOKEN."

        time.sleep(0.3)
        assert os.path.exists(log_path), f"Audit log {log_path} was not created."
        with open(log_path, "r") as f:
            log_content = f.read()
        new_log = log_content[old_size:]

        # Preserve the original log assertions and additionally require one
        # redacted entry for each unpredictable request.
        assert "[REDACTED]" in log_content, "The string [REDACTED] was not found in the audit log."
        assert new_log.count("[REDACTED]") >= len(tokens), "Each request must log a redacted token."
        for token in tokens:
            assert token not in log_content, f"The sensitive token '{token}' was leaked in the audit log!"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTPS service or verify certificate: {e}")
    finally:
        with open(WORKER, "wb") as f:
            f.write(original_worker)
        os.chmod(WORKER, original_mode)
        shutil.rmtree(capture_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
