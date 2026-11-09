#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import shutil
import stat
import subprocess
from datetime import datetime, timezone

SCRIPT_PATH = "/home/user/setup_baseline.sh"
SERVICE_PATH = "/home/user/service"
BASELINE_PATH = "/home/user/baseline_size.txt"
RUN_START = None
RUN_END = None


def run_checked(args, *, input_data=None):
    result = subprocess.run(
        args,
        input=input_data,
        capture_output=True,
        text=False,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Command {args!r} failed with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.islink(path) or not os.path.isdir(path):
        os.unlink(path)
    else:
        shutil.rmtree(path)


def test_script_exists_and_executable():
    global RUN_START, RUN_END

    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    # Remove any pre-created outputs so the submitted script must produce them.
    remove_path(SERVICE_PATH)
    remove_path(BASELINE_PATH)

    RUN_START = datetime.now(timezone.utc)
    result = subprocess.run(
        ["bash", SCRIPT_PATH], capture_output=True, text=True, timeout=60
    )
    RUN_END = datetime.now(timezone.utc)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"


def test_directories_created():
    dirs = [
        "/home/user/service/www",
        "/home/user/service/logs",
        "/home/user/service/certs",
    ]
    for directory in dirs:
        assert os.path.isdir(directory), f"Directory {directory} was not created."


def test_symlink_created():
    symlink_path = "/home/user/service/current_logs"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), target))
    assert target == "/home/user/service/logs", (
        f"Symlink points to {target} instead of /home/user/service/logs"
    )


def test_certificates_generated():
    cert_path = "/home/user/service/certs/cert.pem"
    key_path = "/home/user/service/certs/key.pem"

    assert os.path.isfile(cert_path), f"Certificate {cert_path} missing."
    assert os.path.isfile(key_path), f"Private key {key_path} missing."

    with open(cert_path, "r") as cert_file:
        cert_content = cert_file.read()
    assert "BEGIN CERTIFICATE" in cert_content, (
        "cert.pem does not look like a valid PEM certificate."
    )

    with open(key_path, "r") as key_file:
        key_content = key_file.read()
    assert "PRIVATE KEY" in key_content, (
        "key.pem does not look like a valid PEM private key."
    )
    assert "ENCRYPTED" not in key_content, "The private key must be unencrypted."

    # Parse the artifacts and require a valid 2048-bit RSA private key.
    run_checked(["openssl", "x509", "-in", cert_path, "-noout"])
    run_checked(["openssl", "rsa", "-in", key_path, "-check", "-noout"])
    key_description = run_checked(
        ["openssl", "pkey", "-in", key_path, "-text", "-noout"]
    ).decode(errors="replace")
    assert re.search(r"(?:Private-Key|RSA Private-Key):\s*\(2048 bit(?:,|\))", key_description), (
        "The private key is not a 2048-bit RSA key."
    )

    # Require the certificate and private key to contain the same public key.
    cert_public_pem = run_checked(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"]
    )
    cert_public_der = run_checked(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input_data=cert_public_pem,
    )
    key_public_der = run_checked(
        ["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"]
    )
    assert cert_public_der == key_public_der, (
        "The certificate and private key are not a matching keypair."
    )

    identity = run_checked([
        "openssl", "x509", "-in", cert_path, "-noout",
        "-subject", "-issuer", "-nameopt", "RFC2253",
    ]).decode()
    identity_fields = {}
    for line in identity.splitlines():
        name, separator, value = line.partition("=")
        if separator:
            identity_fields[name.strip()] = value.strip()
    assert identity_fields.get("subject") == "CN=capacity.local", (
        f"Unexpected certificate subject: {identity_fields.get('subject')!r}"
    )
    assert identity_fields.get("issuer") == identity_fields.get("subject"), (
        "Certificate issuer and subject differ; it is not self-signed."
    )
    verification = run_checked(
        ["openssl", "verify", "-CAfile", cert_path, cert_path]
    ).decode(errors="replace")
    assert verification.strip().endswith(": OK"), (
        "Certificate self-signature verification failed."
    )

    dates = run_checked(
        ["openssl", "x509", "-in", cert_path, "-noout", "-dates"]
    ).decode()
    date_fields = dict(line.split("=", 1) for line in dates.splitlines() if "=" in line)
    not_before = datetime.strptime(
        date_fields["notBefore"], "%b %d %H:%M:%S %Y GMT"
    ).replace(tzinfo=timezone.utc)
    not_after = datetime.strptime(
        date_fields["notAfter"], "%b %d %H:%M:%S %Y GMT"
    ).replace(tzinfo=timezone.utc)
    assert (not_after - not_before).total_seconds() == 30 * 24 * 60 * 60, (
        "Certificate validity period is not exactly 30 days."
    )
    assert RUN_START.timestamp() - 5 <= not_before.timestamp() <= RUN_END.timestamp() + 5, (
        "Certificate was not generated when the submitted script ran."
    )


def test_logrotate_config():
    conf_path = "/home/user/service/logrotate.conf"
    assert os.path.isfile(conf_path), f"Logrotate config {conf_path} missing."

    with open(conf_path, "r") as conf_file:
        content = conf_file.read()

    # Preserve the original presence assertions.
    assert "/home/user/service/logs/*.log" in content, (
        "Logrotate config missing target log path."
    )
    assert re.search(r"\bdaily\b", content), "Logrotate config missing 'daily'."
    assert re.search(r"\brotate\s+7\b", content), "Logrotate config missing 'rotate 7'."
    assert re.search(r"\bcompress\b", content), "Logrotate config missing 'compress'."

    # Ignore comments, then require the directives to be active in the target stanza.
    active_content = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    matching_bodies = []
    for match in re.finditer(r"([^{}]+)\{([^{}]*)\}", active_content, re.DOTALL):
        header = match.group(1).strip().splitlines()[-1].strip()
        try:
            targets = shlex.split(header)
        except ValueError as error:
            raise AssertionError(f"Invalid logrotate stanza header: {error}")
        if "/home/user/service/logs/*.log" in targets:
            matching_bodies.append(match.group(2))

    assert len(matching_bodies) == 1, (
        "Expected exactly one active stanza for /home/user/service/logs/*.log."
    )
    directives = [
        line.strip().split()
        for line in matching_bodies[0].splitlines()
        if line.strip()
    ]
    assert ["daily"] in directives, "Target stanza does not actively specify daily."
    assert ["rotate", "7"] in directives, "Target stanza does not actively specify rotate 7."
    assert ["compress"] in directives, "Target stanza does not actively specify compress."

    frequency_words = {"hourly", "daily", "weekly", "monthly", "yearly"}
    active_frequencies = [parts[0] for parts in directives if parts[0] in frequency_words]
    assert active_frequencies == ["daily"], (
        f"Target stanza has conflicting rotation frequencies: {active_frequencies}"
    )
    rotate_directives = [parts for parts in directives if parts[0] == "rotate"]
    assert rotate_directives == [["rotate", "7"]], (
        f"Target stanza has conflicting rotate directives: {rotate_directives}"
    )
    assert not any(parts[0] == "nocompress" for parts in directives), (
        "Target stanza disables compression with nocompress."
    )


def test_dummy_log():
    log_path = "/home/user/service/logs/access.log"
    assert os.path.isfile(log_path), f"Dummy log {log_path} missing."

    with open(log_path, "r") as log_file:
        lines = log_file.read().splitlines()

    assert len(lines) == 1000, f"Expected 1000 lines in access.log, found {len(lines)}."
    assert lines[0] == "dummy log entry", "Log entry content does not match expected."
    assert all(line == "dummy log entry" for line in lines), (
        "Every line in access.log must be exactly 'dummy log entry'."
    )


def test_baseline_size():
    assert os.path.isfile(BASELINE_PATH), f"Baseline size file {BASELINE_PATH} missing."

    with open(BASELINE_PATH, "r") as size_file:
        raw_content = size_file.read()
    content = raw_content.strip()

    assert content.isdigit(), f"Baseline size file contains non-numeric data: {content}"
    assert re.fullmatch(r"[0-9]+\n?", raw_content), (
        "Baseline size file must contain only the numeric byte value."
    )

    result = subprocess.run(
        ["/usr/bin/du", "-sb", SERVICE_PATH], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"du failed: {result.stderr}"
    actual_size = result.stdout.split()[0]
    assert content == actual_size, (
        f"Baseline size {content} does not match actual size {actual_size}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
