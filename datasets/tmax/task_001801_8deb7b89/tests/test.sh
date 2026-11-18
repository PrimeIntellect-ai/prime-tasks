#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import os
import re
import signal
import ssl
import subprocess
import time
import urllib.request
from difflib import SequenceMatcher

SERVER_PROC = None
SERVER_LOG = None
CERT_DER = None
PORT_HEX = "20FB"  # 8443


def listening_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[-1].upper() == PORT_HEX and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def pid_owns_inode(pid, inodes):
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                return True
    except FileNotFoundError:
        return False
    return False


def stop_existing_listener():
    inodes = listening_inodes()
    if not inodes:
        return
    victims = []
    for entry in os.listdir("/proc"):
        if entry.isdigit() and pid_owns_inode(int(entry), inodes):
            victims.append(int(entry))
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listening_inodes() and time.time() < deadline:
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listening_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listening_inodes(), "Could not stop the pre-existing service on port 8443."


def cleanup():
    global SERVER_PROC, SERVER_LOG
    if SERVER_PROC is not None and SERVER_PROC.poll() is None:
        SERVER_PROC.terminate()
        try:
            SERVER_PROC.wait(timeout=2)
        except subprocess.TimeoutExpired:
            SERVER_PROC.kill()
    if SERVER_LOG is not None:
        SERVER_LOG.close()


atexit.register(cleanup)


def test_expect_script_exists():
    """Check if the expect script was created."""
    path = "/home/user/automate.exp"
    assert os.path.isfile(path), f"Expect script {path} is missing."


def test_c_source_and_binary_exists():
    """Check if the C server source and compiled binary exist."""
    src_path = "/home/user/server.c"
    bin_path = "/home/user/server"
    assert os.path.isfile(src_path), f"C source file {src_path} is missing."
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"Binary {bin_path} is not executable."


def test_certificates_exist():
    """Check if the self-signed certificates were generated."""
    cert_path = "/home/user/cert.pem"
    key_path = "/home/user/key.pem"
    assert os.path.isfile(cert_path), f"Certificate file {cert_path} is missing."
    assert os.path.isfile(key_path), f"Key file {key_path} is missing."


def test_actual_expect_automation_and_c_openssl_server():
    global SERVER_PROC, SERVER_LOG, CERT_DER

    # Derive the expected transcript by exercising the supplied transcriber itself.
    expected_path = "/tmp/verifier_expected_transcript.txt"
    try:
        os.unlink(expected_path)
    except FileNotFoundError:
        pass
    direct = subprocess.run(
        ["/app/interactive_transcriber"],
        input=f"/app/voicemail.wav\n{expected_path}\n",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert direct.returncode == 0, f"Supplied transcriber failed: {direct.stdout}"
    with open(expected_path, "rb") as f:
        expected = f.read()
    assert expected, "The supplied transcriber produced no transcript."

    # Interpose a transparent marker so merely writing a fixed transcript does not
    # pass: automate.exp must really spawn the required transcriber path.
    real = "/app/interactive_transcriber.__verifier_real"
    marker = "/tmp/verifier_transcriber_invoked"
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass
    assert not os.path.exists(real), f"Unexpected verifier backup path already exists: {real}"
    os.rename("/app/interactive_transcriber", real)
    try:
        with open("/app/interactive_transcriber", "w") as f:
            f.write("#!/bin/sh\nprintf invoked > /tmp/verifier_transcriber_invoked\nexec /app/interactive_transcriber.__verifier_real \"$@\"\n")
        os.chmod("/app/interactive_transcriber", 0o755)
        try:
            os.unlink("/home/user/transcript.txt")
        except FileNotFoundError:
            pass
        automated = subprocess.run(
            ["expect", "/home/user/automate.exp"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=15,
        )
    finally:
        try:
            os.unlink("/app/interactive_transcriber")
        except FileNotFoundError:
            pass
        os.rename(real, "/app/interactive_transcriber")

    assert automated.returncode == 0, f"Expect automation failed: {automated.stdout}"
    assert os.path.isfile(marker), "automate.exp did not run /app/interactive_transcriber."
    assert os.path.isfile("/home/user/transcript.txt"), "Automation did not create transcript.txt."
    with open("/home/user/transcript.txt", "rb") as f:
        actual = f.read()
    assert actual == expected, "The automated transcript differs from the transcriber's output."

    # Validate the submitted certificate and matching private key.
    cert_check = subprocess.run(
        ["openssl", "x509", "-in", "/home/user/cert.pem", "-noout", "-checkend", "0"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    assert cert_check.returncode == 0, f"Invalid or expired certificate: {cert_check.stderr}"
    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", "/home/user/cert.pem", "-pubkey", "-noout"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", "/home/user/key.pem", "-pubout"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout
    assert cert_pub == key_pub, "cert.pem and key.pem do not form a matching pair."
    subject = subprocess.run(
        ["openssl", "x509", "-in", "/home/user/cert.pem", "-noout", "-subject", "-nameopt", "RFC2253"],
        check=True, stdout=subprocess.PIPE, text=True,
    ).stdout.strip().split("=", 1)[-1]
    issuer = subprocess.run(
        ["openssl", "x509", "-in", "/home/user/cert.pem", "-noout", "-issuer", "-nameopt", "RFC2253"],
        check=True, stdout=subprocess.PIPE, text=True,
    ).stdout.strip().split("=", 1)[-1]
    assert subject == issuer, "cert.pem is not self-signed."
    with open("/home/user/cert.pem") as f:
        CERT_DER = ssl.PEM_cert_to_DER_cert(f.read())

    # Compile the submitted C source into the demanded output path.
    built = "/home/user/server.verifier-build"
    compile_result = subprocess.run(
        ["gcc", "/home/user/server.c", "-o", built, "-lssl", "-lcrypto"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"server.c does not compile with OpenSSL: {compile_result.stdout}"
    os.replace(built, "/home/user/server")
    os.chmod("/home/user/server", 0o755)

    dynamic_symbols = subprocess.run(
        ["nm", "-D", "/home/user/server"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    ).stdout
    assert re.search(r"\bU\s+SSL_[A-Za-z0-9_]+", dynamic_symbols), \
        "The compiled C server does not import the OpenSSL TLS API."

    stop_existing_listener()
    SERVER_LOG = open("/tmp/verifier_server.log", "w+")
    SERVER_PROC = subprocess.Popen(
        ["/home/user/server"], cwd="/home/user", stdout=SERVER_LOG, stderr=subprocess.STDOUT
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        inodes = listening_inodes()
        if inodes and pid_owns_inode(SERVER_PROC.pid, inodes):
            break
        if SERVER_PROC.poll() is not None:
            SERVER_LOG.flush()
            SERVER_LOG.seek(0)
            assert False, f"Compiled server exited before listening: {SERVER_LOG.read()}"
        time.sleep(0.05)
    else:
        assert False, "The freshly compiled /home/user/server did not bind port 8443."


def test_transcript_served_over_https():
    """Fetch the transcript from the HTTPS server and verify its accuracy."""
    truth = "Alert system failure detected on node seven. Please restart the primary database daemon immediately."

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    url = "https://127.0.0.1:8443/"
    try:
        req = urllib.request.urlopen(url, context=ctx, timeout=5)
        peer_der = req.fp.raw._sock.getpeercert(binary_form=True)
        result = req.read().decode("utf-8").strip()
    except Exception as e:
        assert False, f"Failed to fetch transcript from {url}: {e}"

    assert peer_der == CERT_DER, "The TLS service did not use /home/user/cert.pem."
    ratio = SequenceMatcher(None, truth.lower(), result.lower()).ratio()
    assert ratio >= 0.90, f"Transcript similarity ratio {ratio:.4f} is below the threshold of 0.90. Fetched: '{result}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
