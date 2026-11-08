#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import shlex
import string
import subprocess
import tempfile

SOURCE_DIR = "/app/msmtp-1.8.24"
PREFIX = "/home/user/local"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def assert_compiled_binary(installed, built):
    assert os.path.isfile(installed), f"{installed} does not exist. Was it installed correctly?"
    assert os.access(installed, os.X_OK), f"{installed} is not executable."
    assert os.path.isfile(built), f"Expected build artifact {built} is missing."
    with open(installed, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{installed} is not a compiled ELF binary."
    assert sha256(installed) == sha256(built), \
        f"{installed} does not match the binary built from the vendored source."


def test_build_was_fixed_and_configured():
    makefile_in = os.path.join(SOURCE_DIR, "Makefile.in")
    makefile = os.path.join(SOURCE_DIR, "Makefile")
    config_status = os.path.join(SOURCE_DIR, "config.status")

    assert os.path.isfile(makefile_in)
    with open(makefile_in, encoding="utf-8", errors="replace") as f:
        template = f.read()
    assert re.search(r"(?m)^install\s*:", template), \
        "The install target in Makefile.in was not repaired."
    assert not re.search(r"(?m)^nstall\s*:", template), \
        "The deliberately broken nstall target remains in Makefile.in."

    assert os.path.isfile(makefile), "The package was not configured."
    assert os.path.isfile(config_status), "config.status is missing; the package was not configured."
    result = subprocess.run([config_status, "--config"], cwd=SOURCE_DIR,
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, "Could not inspect the package configuration."
    assert "--prefix=/home/user/local" in result.stdout, \
        f"Package was not configured with the required prefix: {result.stdout}"

    object_files = []
    for root, _, files in os.walk(os.path.join(SOURCE_DIR, "src")):
        object_files.extend(os.path.join(root, n) for n in files if n.endswith(".o"))
    assert object_files, "No compiled object files were found in the vendored build tree."


def test_msmtp_installed():
    msmtp_bin = "/home/user/local/bin/msmtp"
    assert_compiled_binary(msmtp_bin, os.path.join(SOURCE_DIR, "src", "msmtp"))

    result = subprocess.run([msmtp_bin, "--version"], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Running {msmtp_bin} --version failed."
    assert "1.8.24" in result.stdout, f"Expected version 1.8.24 in output, got: {result.stdout}"

    msmtpd_bin = "/home/user/local/bin/msmtpd"
    assert_compiled_binary(msmtpd_bin, os.path.join(SOURCE_DIR, "src", "msmtpd"))
    daemon_version = subprocess.run([msmtpd_bin, "--version"], capture_output=True,
                                    text=True, timeout=10)
    assert daemon_version.returncode == 0, f"Running {msmtpd_bin} --version failed."
    assert "1.8.24" in daemon_version.stdout, \
        f"Expected msmtpd version 1.8.24, got: {daemon_version.stdout}"


def test_systemd_unit_file():
    unit_file = "/home/user/.config/systemd/user/msmtp-relay.service"
    assert os.path.isfile(unit_file), f"Systemd unit file {unit_file} is missing."

    with open(unit_file, "r") as f:
        content = f.read()

    assert "ExecStart=/home/user/local/bin/msmtpd" in content, \
        f"Unit file does not contain ExecStart=/home/user/local/bin/msmtpd. Content:\n{content}"

    section = None
    service_commands = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line
        elif section == "[Service]" and line.startswith("ExecStart="):
            service_commands.append(line.split("=", 1)[1].strip())

    assert service_commands, "The unit has no active ExecStart directive in its [Service] section."
    assert any(shlex.split(command) and shlex.split(command)[0] == "/home/user/local/bin/msmtpd"
               for command in service_commands), \
        "The active service command does not run the installed msmtpd binary."
    assert os.path.isfile("/home/user/local/bin/msmtpd")
    assert os.access("/home/user/local/bin/msmtpd", os.X_OK)


def expected_route(email_content):
    normalized = email_content.replace("\r\n", "\n")
    header_text = normalized.split("\n\n", 1)[0]
    list_ids = []
    subjects = []
    for line in header_text.splitlines():
        if re.match(r"^List-Id:", line, re.IGNORECASE):
            list_ids.append(line.split(":", 1)[1])
        elif re.match(r"^Subject:", line, re.IGNORECASE):
            subjects.append(line.split(":", 1)[1])

    combined_list_ids = "\n".join(list_ids).lower()
    if "dev.local" in combined_list_ids:
        return "ROUTE_TO: 8081"
    if "announce.local" in combined_list_ids:
        return "ROUTE_TO: 8082"
    if not list_ids and any("[urgent]" in subject.lower() for subject in subjects):
        return "ROUTE_TO: 8089"
    return "ROUTE_TO: 8080"


def generate_fuzz_email(rng):
    headers = []

    if rng.random() < 0.6:
        for _ in range(rng.randint(1, 2)):
            value = rng.choice([
                "dev.local", "announce.local", "other.local", "DEV.LOCAL",
                "AnNoUnCe.LoCaL", "project.dev.local.example", "devXlocal"
            ])
            name = rng.choice(["List-Id", "list-id", "LIST-ID", "List-id"])
            headers.append(f"{name}: {value}")

    if rng.random() < 0.65:
        value = rng.choice([
            "[URGENT] help", "normal email", "[urgent] stuff", "[URGENT]",
            "prefix [UrGeNt] suffix", "URGENT without brackets"
        ])
        name = rng.choice(["Subject", "subject", "SUBJECT", "SubJect"])
        headers.append(f"{name}: {value}")

    for _ in range(rng.randint(1, 5)):
        name = "X-" + "".join(rng.choices(string.ascii_letters, k=rng.randint(5, 10)))
        value = "".join(rng.choices(string.ascii_letters + string.digits + " .[]", k=rng.randint(10, 50)))
        headers.append(f"{name}: {value}")

    rng.shuffle(headers)
    body = "".join(rng.choices(string.ascii_letters + string.digits + " \n", k=rng.randint(20, 100)))
    newline = rng.choice(["\n", "\r\n"])
    return newline.join(headers) + newline * 2 + body


def test_fuzz_equivalence():
    agent_script = "/home/user/mail_router.sh"
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."

    rng = random.SystemRandom()
    fixed = [
        "List-Id: dev.local\nSubject: normal\n\nbody",
        "LIST-ID: ANNOUNCE.LOCAL\n\nbody",
        "Subject: [urgent] help\n\nbody",
        "Subject: normal\n\nbody",
        "List-Id: other.local\nSubject: [URGENT]\n\nbody",
        "List-Id: announce.local\nList-Id: dev.local\n\nbody",
        "Subject: prefix [UrGeNt] suffix\r\n\r\nbody",
    ]
    emails = fixed + [generate_fuzz_email(rng) for _ in range(500 - len(fixed))]

    with tempfile.TemporaryDirectory() as tmpdir:
        for i, email_content in enumerate(emails):
            input_file = os.path.join(tmpdir, f"email_{i}.txt")
            with open(input_file, "w", newline="") as f:
                f.write(email_content)

            result = subprocess.run(["bash", agent_script, input_file],
                                    capture_output=True, text=True, timeout=2)
            assert result.returncode == 0, f"Agent script failed on input {i}: {result.stderr}"

            expected = expected_route(email_content)
            actual = result.stdout.strip()
            assert actual == expected, \
                f"Mismatch on fuzz input {i}!\nInput:\n{email_content}\n\nExpected: {expected}\nGot: {actual}"
            assert result.stdout in (expected, expected + "\n"), \
                f"Output must be exactly one routing line; got {result.stdout!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
