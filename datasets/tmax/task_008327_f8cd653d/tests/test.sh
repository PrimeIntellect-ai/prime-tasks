#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import ssl
import subprocess


def run(command, *, input_data=None, timeout=10):
    return subprocess.run(
        command,
        input=input_data,
        capture_output=True,
        text=False,
        check=False,
        timeout=timeout,
    )


def test_service_file_fixed():
    service_path = "/home/user/.config/systemd/user/secure-app.service"
    assert os.path.isfile(service_path), f"Service file {service_path} is missing."

    with open(service_path, "r") as f:
        content = f.read()

    assert "LimitFSIZE" not in content, "LimitFSIZE directive was not removed from the service file."

    exec_starts = []
    for line in content.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith(("#", ";")) and stripped.startswith("ExecStart="):
            exec_starts.append(stripped.split("=", 1)[1].strip())
    assert exec_starts == ["/home/user/app/run.sh"], \
        f"secure-app.service must run /home/user/app/run.sh, found ExecStart values: {exec_starts}"


def test_tls_certificates_exist():
    cert_path = "/home/user/app/cert.pem"
    key_path = "/home/user/app/key.pem"

    assert os.path.isfile(cert_path), f"Certificate file {cert_path} is missing."
    assert os.path.isfile(key_path), f"Private key file {key_path} is missing."

    with open(key_path, "rb") as f:
        key_contents = f.read()
    assert b"ENCRYPTED" not in key_contents.upper(), "The private key must be unencrypted."

    key_check = run(["openssl", "rsa", "-in", key_path, "-check", "-noout"])
    assert key_check.returncode == 0, \
        f"key.pem is not a valid unencrypted RSA private key: {key_check.stderr.decode(errors='replace')}"

    key_text = run(["openssl", "rsa", "-in", key_path, "-text", "-noout"])
    assert key_text.returncode == 0 and b"2048 bit" in key_text.stdout, \
        "key.pem must be an RSA 2048-bit private key."

    cert_check = run(["openssl", "x509", "-in", cert_path, "-noout", "-checkend", "0"])
    assert cert_check.returncode == 0, \
        f"cert.pem is not a currently valid X.509 certificate: {cert_check.stderr.decode(errors='replace')}"

    subject_result = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"])
    assert subject_result.returncode == 0
    subject = subject_result.stdout.decode(errors="replace").strip()
    subject_value = subject.split("=", 1)[1] if "=" in subject else ""
    assert "CN=localhost" in subject_value.split(","), \
        f"Certificate Common Name must be localhost, found: {subject}"

    issuer_result = run(["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"])
    assert issuer_result.returncode == 0
    issuer = issuer_result.stdout.decode(errors="replace").strip()
    issuer_value = issuer.split("=", 1)[1] if "=" in issuer else ""
    assert issuer_value == subject_value, "cert.pem must be self-signed."

    verify_result = run(["openssl", "verify", "-CAfile", cert_path, cert_path])
    assert verify_result.returncode == 0, \
        f"The self-signed certificate signature is invalid: {verify_result.stderr.decode(errors='replace')}"

    cert_pub = run(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    assert cert_pub.returncode == 0
    cert_pub_der = run(["openssl", "pkey", "-pubin", "-outform", "DER"], input_data=cert_pub.stdout)
    key_pub_der = run(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"])
    assert cert_pub_der.returncode == 0 and key_pub_der.returncode == 0
    assert cert_pub_der.stdout == key_pub_der.stdout, "cert.pem and key.pem do not form a matching pair."


def service_processes(main_pid):
    processes = {main_pid}
    changed = True
    while changed:
        changed = False
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            pid = int(entry)
            try:
                with open(f"/proc/{pid}/stat", "r") as f:
                    stat = f.read()
                tail = stat[stat.rfind(")") + 2:].split()
                ppid = int(tail[1])
            except (OSError, ValueError, IndexError):
                continue
            if ppid in processes and pid not in processes:
                processes.add(pid)
                changed = True
    return processes


def test_service_is_active():
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "secure-app.service"],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        assert result.stdout.strip() == "active", f"Service is not active. Output: {result.stdout.strip()}"
    except FileNotFoundError:
        assert False, "systemctl command not found."

    pid_result = subprocess.run(
        ["systemctl", "--user", "show", "secure-app.service", "--property=MainPID", "--value"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    assert pid_result.returncode == 0 and pid_result.stdout.strip().isdigit()
    main_pid = int(pid_result.stdout.strip())
    assert main_pid > 0, "secure-app.service has no running main process."

    listening_inodes = set()
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            if len(fields) > 9 and fields[1] == "0100007F:20FB" and fields[3] == "0A":
                listening_inodes.add(fields[9])
    assert listening_inodes, "Nothing is listening on 127.0.0.1:8443."

    owned_by_service = False
    for pid in service_processes(main_pid):
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in listening_inodes:
                    owned_by_service = True
                    break
        except OSError:
            continue
        if owned_by_service:
            break
    assert owned_by_service, "The HTTPS listener on port 8443 is not running under secure-app.service."


def test_success_file_contains_200():
    success_path = "/home/user/success.txt"
    assert os.path.isfile(success_path), f"File {success_path} is missing."

    with open(success_path, "r") as f:
        content = f.read().strip()

    assert content == "200", f"Expected success.txt to contain '200', but found '{content}'."

    curl_result = subprocess.run(
        [
            "curl", "--insecure", "--silent", "--show-error",
            "--output", "/dev/null", "--write-out", "%{http_code}",
            "--connect-timeout", "5", "--max-time", "10",
            "https://127.0.0.1:8443",
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    actual_code = curl_result.stdout.strip()
    assert curl_result.returncode == 0, f"HTTPS query failed: {curl_result.stderr.strip()}"
    assert actual_code == "200", f"Expected the live HTTPS server to return 200, got {actual_code}."
    assert content == actual_code, "success.txt does not contain the status returned by the live server."

    context = ssl._create_unverified_context()
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw_socket:
        with context.wrap_socket(raw_socket, server_hostname="localhost") as tls_socket:
            served_der = tls_socket.getpeercert(binary_form=True)

    cert_der = run(["openssl", "x509", "-in", "/home/user/app/cert.pem", "-outform", "DER"])
    assert cert_der.returncode == 0
    assert served_der == cert_der.stdout, "The server is not presenting /home/user/app/cert.pem."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
