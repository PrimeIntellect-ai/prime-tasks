#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import datetime
import gzip
import os
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

PROFILE = "/home/user/.bash_profile"
SETUP_TLS = "/home/user/setup_tls.sh"
ROTATE = "/home/user/rotate.sh"
DEPLOY = "/home/user/deploy.sh"
EXPECTED_LINE = "Starting server on port 8443 with cert /home/user/tls/server.crt"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 30)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def certificate_details(crt_path, key_path):
    subject_result = run([
        "openssl", "x509", "-in", crt_path, "-noout", "-subject",
        "-nameopt", "RFC2253"
    ])
    subject = subject_result.stdout.strip()
    assert subject.startswith("subject="), f"Unexpected subject output: {subject}"
    normalized_subject = subject.split("=", 1)[1].replace(" ", "")
    assert normalized_subject == "CN=localhost,O=Company,L=City,ST=State,C=US", (
        f"Certificate subject is not exact: {subject}"
    )

    key_info = run(["openssl", "rsa", "-in", key_path, "-noout", "-text"]).stdout
    assert re.search(r"Private-Key:\s*\(2048 bit", key_info), "Key is not RSA 2048-bit."

    cert_pub = subprocess.run(
        ["bash", "-c", f"openssl x509 -in {crt_path!r} -pubkey -noout | openssl pkey -pubin -outform DER"],
        capture_output=True,
        timeout=30,
    )
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"],
        capture_output=True,
        timeout=30,
    )
    assert cert_pub.returncode == 0 and key_pub.returncode == 0, "Could not extract public keys."
    assert cert_pub.stdout == key_pub.stdout, "Certificate and private key do not match."

    dates = run(["openssl", "x509", "-in", crt_path, "-noout", "-dates"]).stdout.splitlines()
    values = dict(line.split("=", 1) for line in dates)
    not_before = datetime.datetime.strptime(values["notBefore"], "%b %d %H:%M:%S %Y %Z")
    not_after = datetime.datetime.strptime(values["notAfter"], "%b %d %H:%M:%S %Y %Z")
    assert not_after - not_before == datetime.timedelta(days=30), (
        f"Certificate validity is not exactly 30 days: {not_before} to {not_after}"
    )


def test_bash_profile_env_vars():
    assert os.path.isfile(PROFILE), f"{PROFILE} does not exist."
    with open(PROFILE, "r") as f:
        content = f.read()

    # Preserve the original textual assertions.
    assert "APP_PORT=8443" in content, "APP_PORT=8443 missing in .bash_profile"
    assert "APP_LOG_DIR=/home/user/app_logs" in content, "APP_LOG_DIR=/home/user/app_logs missing in .bash_profile"
    assert "TLS_DIR=/home/user/tls" in content, "TLS_DIR=/home/user/tls missing in .bash_profile"

    # Ensure these are active, exported assignments rather than comments or inert text.
    command = (
        f"source {PROFILE!r} >/dev/null; "
        "test \"$APP_PORT\" = 8443; "
        "test \"$APP_LOG_DIR\" = /home/user/app_logs; "
        "test \"$TLS_DIR\" = /home/user/tls; "
        "bash -c 'test \"$APP_PORT\" = 8443 && "
        "test \"$APP_LOG_DIR\" = /home/user/app_logs && "
        "test \"$TLS_DIR\" = /home/user/tls'"
    )
    run(["bash", "-c", command])


def test_tls_certificates_exist_and_valid():
    crt_path = "/home/user/tls/server.crt"
    key_path = "/home/user/tls/server.key"
    assert os.path.isfile(crt_path), f"Certificate {crt_path} does not exist."
    assert os.path.isfile(key_path), f"Key {key_path} does not exist."

    # Preserve the original subject component checks.
    result = run(["openssl", "x509", "-in", crt_path, "-noout", "-subject"])
    subject = result.stdout
    assert "C = US" in subject or "C=US" in subject
    assert "ST = State" in subject or "ST=State" in subject
    assert "L = City" in subject or "L=City" in subject
    assert "O = Company" in subject or "O=Company" in subject
    assert "CN = localhost" in subject or "CN=localhost" in subject

    certificate_details(crt_path, key_path)


def test_log_rotation_artifacts():
    log_bak_gz = "/home/user/app_logs/server.log.bak.gz"
    assert os.path.isfile(log_bak_gz), (
        f"Rotated log archive {log_bak_gz} does not exist. Did you run deploy.sh twice as instructed?"
    )
    with gzip.open(log_bak_gz, "rb") as f:
        assert len(f.read()) > 1000, "Rotated archive does not contain a log larger than 1000 bytes."


def test_current_log_file():
    log_file = "/home/user/app_logs/server.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."
    with open(log_file, "r") as f:
        content = f.read()
    assert EXPECTED_LINE in content, f"Log file does not contain the expected startup message. Found: {content}"


def test_scripts_are_executable_bash_scripts():
    for script in [SETUP_TLS, ROTATE, DEPLOY]:
        assert os.path.isfile(script), f"Script {script} does not exist."
        st = os.stat(script)
        assert bool(st.st_mode & stat.S_IXUSR), f"Script {script} is not executable."
        with open(script, "rb") as f:
            first_line = f.readline().decode("utf-8", "replace").strip()
        assert first_line.startswith("#!") and "bash" in first_line, f"{script} is not a bash script."


def test_setup_tls_script_behavior():
    with tempfile.TemporaryDirectory() as root:
        tls_dir = os.path.join(root, "nested", "tls")
        env = os.environ.copy()
        env["TLS_DIR"] = tls_dir
        run([SETUP_TLS], env=env)
        crt_path = os.path.join(tls_dir, "server.crt")
        key_path = os.path.join(tls_dir, "server.key")
        assert os.path.isfile(crt_path), "setup_tls.sh did not create server.crt in $TLS_DIR."
        assert os.path.isfile(key_path), "setup_tls.sh did not create server.key in $TLS_DIR."
        certificate_details(crt_path, key_path)


def test_rotate_script_behavior():
    with tempfile.TemporaryDirectory() as log_dir:
        env = os.environ.copy()
        env["APP_LOG_DIR"] = log_dir
        log_path = os.path.join(log_dir, "server.log")
        gz_path = os.path.join(log_dir, "server.log.bak.gz")

        # A missing log must not be fabricated or rotated.
        run([ROTATE], env=env)
        assert not os.path.exists(log_path)
        assert not os.path.exists(gz_path)

        # Exactly 1000 bytes is not strictly greater than the threshold.
        small = b"s" * 1000
        with open(log_path, "wb") as f:
            f.write(small)
        with open(gz_path, "wb") as f:
            f.write(b"old archive")
        run([ROTATE], env=env)
        assert open(log_path, "rb").read() == small
        assert open(gz_path, "rb").read() == b"old archive"

        # A larger file must be copied, gzipped with overwrite, and truncated in place.
        payload = os.urandom(2001)
        with open(log_path, "wb") as f:
            f.write(payload)
        os.chmod(log_path, 0o640)
        before = os.stat(log_path)
        run([ROTATE], env=env)
        after = os.stat(log_path)
        assert after.st_size == 0, "rotate.sh did not truncate server.log."
        assert after.st_ino == before.st_ino, "rotate.sh replaced/deleted server.log instead of truncating it."
        assert stat.S_IMODE(after.st_mode) == stat.S_IMODE(before.st_mode), "rotate.sh changed log permissions."
        assert os.path.isfile(gz_path), "rotate.sh did not create server.log.bak.gz."
        with gzip.open(gz_path, "rb") as f:
            assert f.read() == payload, "Rotated gzip does not contain the original log bytes."


def test_deploy_executes_dependencies_in_exact_order():
    work = tempfile.mkdtemp(prefix="verify-deploy-")
    backups = {}
    app_logs = "/home/user/app_logs"
    saved_logs = os.path.join(work, "saved_app_logs")
    trace = os.path.join(work, "trace")
    marker = os.path.join(work, "setup_done")

    try:
        for path in (SETUP_TLS, ROTATE):
            backup = os.path.join(work, os.path.basename(path) + ".original")
            os.replace(path, backup)
            backups[path] = backup

        if os.path.exists(app_logs):
            os.replace(app_logs, saved_logs)

        setup_wrapper = f'''#!/bin/bash
set -e
test "$APP_PORT" = "8443"
test "$APP_LOG_DIR" = "/home/user/app_logs"
test "$TLS_DIR" = "/home/user/tls"
test -d "$APP_LOG_DIR"
echo setup >> {trace!r}
touch {marker!r}
'''
        rotate_wrapper = f'''#!/bin/bash
set -e
test -f {marker!r}
echo rotate >> {trace!r}
'''
        for path, body in ((SETUP_TLS, setup_wrapper), (ROTATE, rotate_wrapper)):
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, 0o755)

        run([DEPLOY])
        with open(trace, "r") as f:
            calls = f.read().splitlines()
        assert calls == ["setup", "rotate"], f"Dependency execution order was {calls}, expected setup then rotate."
        with open(os.path.join(app_logs, "server.log"), "r") as f:
            content = f.read()
        assert EXPECTED_LINE in content, "deploy.sh did not append the startup line after its dependencies."
    finally:
        if os.path.lexists(app_logs):
            if os.path.isdir(app_logs) and not os.path.islink(app_logs):
                shutil.rmtree(app_logs)
            else:
                os.unlink(app_logs)
        if os.path.exists(saved_logs):
            os.replace(saved_logs, app_logs)
        for path, backup in backups.items():
            if os.path.lexists(path):
                os.unlink(path)
            if os.path.exists(backup):
                os.replace(backup, path)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
