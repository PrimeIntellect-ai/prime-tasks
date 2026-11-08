#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import importlib
import os
import shlex
import subprocess
import sys
import tempfile
import uuid

SCRIPT_PATH = "/home/user/ssh_monitor.py"
PARSER_PATH = "/app/ssh_log_parser/parser.py"
CONF_PATH = "/home/user/supervisord.conf"


def run_monitor(directory, executable=False):
    command = [SCRIPT_PATH, directory] if executable else ["python3", SCRIPT_PATH, directory]
    return subprocess.run(command, capture_output=True, text=True, timeout=10)


def parsed_output(stdout):
    classifications = []
    for line in stdout.strip().splitlines():
        if line.startswith("CLEAN:"):
            classifications.append(("CLEAN", line.split(":", 1)[1].strip()))
        elif line.startswith("EVIL:"):
            classifications.append(("EVIL", line.split(":", 1)[1].strip()))
    return classifications


def test_ssh_monitor_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_parser_library_fixed():
    assert os.path.isfile(PARSER_PATH), f"Parser {PARSER_PATH} does not exist."
    sys.path.insert(0, "/app")
    try:
        sys.modules.pop("ssh_log_parser.parser", None)
        parser = importlib.import_module("ssh_log_parser.parser")

        valid_lines = [
            "Accepted publickey for alice from 192.0.2.10 port 40123 ssh2: ssh-ed25519 SHA256:abc",
            "Accepted publickey for bob from 192.0.2.11 port 40124 ssh2: ecdsa-sha2-nistp384 SHA256:def",
            "Accepted publickey for carol from 192.0.2.12 port 40125 ssh2: ssh-rsa SHA256:ghi",
        ]
        invalid_key_lines = [
            "Accepted publickey for mallory from 192.0.2.20 port 40200 ssh2: ssh-dss SHA256:old",
            "Accepted publickey for mallory from 192.0.2.21 port 40201 ssh2: ssh-dss-malformed SHA256:bad",
            "Accepted publickey for mallory from 192.0.2.22 port 40202 ssh2: ssh-rsa-malformed SHA256:bad",
        ]

        for line in valid_lines:
            assert parser.LogEntry(line).is_valid(), f"Parser rejected valid key line: {line}"
        for line in invalid_key_lines:
            assert not parser.LogEntry(line).is_valid(), f"Parser accepted deprecated or malformed key line: {line}"

        assert parser.check_auth_status(valid_lines[0]) is True
        assert parser.check_auth_status("Failed password for root from 192.0.2.30 port 40300 ssh2") is False
        assert parser.check_auth_status("Invalid user admin from 192.0.2.31 port 40301") is False
    finally:
        sys.path.remove("/app")


def test_supervisord_conf():
    assert os.path.isfile(CONF_PATH), f"Config {CONF_PATH} does not exist."
    with open(CONF_PATH, "r") as f:
        content = f.read()
    assert "[program:ssh_monitor_daemon]" in content, f"Config {CONF_PATH} missing [program:ssh_monitor_daemon] section."

    config = configparser.RawConfigParser()
    config.read(CONF_PATH)
    section = "program:ssh_monitor_daemon"
    assert config.has_section(section)

    command = config.get(section, "command", fallback="")
    assert shlex.split(command) == [SCRIPT_PATH, "/app/incoming_logs"], \
        f"Incorrect daemon command: {command!r}"
    assert config.get(section, "autorestart", fallback="").strip().lower() == "true", \
        "ssh_monitor_daemon must have autorestart=true"

    log_paths = {
        config.get(section, "stdout_logfile", fallback="").strip(),
        config.get(section, "stderr_logfile", fallback="").strip(),
    }
    assert "/home/user/daemon.log" in log_paths, \
        "ssh_monitor_daemon must write output to /home/user/daemon.log"


def test_clean_corpus():
    clean_dir = "/app/corpora/clean"
    result = run_monitor(clean_dir)
    assert result.returncode == 0, f"Script failed on clean corpus. Stderr: {result.stderr}"

    output = result.stdout.strip().splitlines()
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".log")]
    evil_flagged = []
    clean_flagged = []
    for line in output:
        if line.startswith("EVIL:"):
            evil_flagged.append(line.split(":", 1)[1].strip())
        elif line.startswith("CLEAN:"):
            clean_flagged.append(line.split(":", 1)[1].strip())

    assert len(evil_flagged) == 0, f"{len(evil_flagged)} of {len(clean_files)} clean logs flagged as EVIL: {', '.join(evil_flagged)}"
    for filename in clean_files:
        assert filename in clean_flagged, f"Clean log {filename} was not flagged as CLEAN."


def test_evil_corpus():
    evil_dir = "/app/corpora/evil"
    result = run_monitor(evil_dir)
    assert result.returncode == 0, f"Script failed on evil corpus. Stderr: {result.stderr}"

    output = result.stdout.strip().splitlines()
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".log")]
    evil_flagged = []
    clean_flagged = []
    for line in output:
        if line.startswith("EVIL:"):
            evil_flagged.append(line.split(":", 1)[1].strip())
        elif line.startswith("CLEAN:"):
            clean_flagged.append(line.split(":", 1)[1].strip())

    assert len(clean_flagged) == 0, f"{len(clean_flagged)} of {len(evil_files)} evil logs flagged as CLEAN: {', '.join(clean_flagged)}"
    for filename in evil_files:
        assert filename in evil_flagged, f"Evil log {filename} was not flagged as EVIL."


def test_classifier_on_generated_logs_and_arbitrary_filenames():
    token = uuid.uuid4().hex
    cases = {
        f"successful_{token}.log": (
            "CLEAN",
            f"Accepted publickey for deploy{token[:6]} from 198.51.100.17 port 45117 ssh2: ssh-ed25519 SHA256:{token}\n",
        ),
        f"ecdsa_{token}.log": (
            "CLEAN",
            f"Accepted publickey for build{token[:6]} from 198.51.100.18 port 45118 ssh2: ecdsa-sha2-nistp256 SHA256:{token}\n",
        ),
        f"deprecated_{token}.log": (
            "EVIL",
            f"Accepted publickey for old{token[:6]} from 203.0.113.20 port 46220 ssh2: ssh-dss SHA256:{token}\n",
        ),
        f"bruteforce_{token}.log": (
            "EVIL",
            "Failed password for invalid user admin from 203.0.113.44 port 47001 ssh2\n"
            "Failed password for invalid user root from 203.0.113.44 port 47002 ssh2\n"
            "Failed password for root from 203.0.113.44 port 47003 ssh2\n",
        ),
        f"malformed_{token}.log": (
            "EVIL",
            f"Accepted publickey for attacker from 203.0.113.55 port 48001 ssh2: ssh-rsa-malformed SHA256:{token}\n",
        ),
    }

    with tempfile.TemporaryDirectory(prefix="ssh-monitor-generated-") as directory:
        for filename, (_, contents) in cases.items():
            with open(os.path.join(directory, filename), "w") as handle:
                handle.write(contents)
        with open(os.path.join(directory, f"ignored_{token}.txt"), "w") as handle:
            handle.write("Failed password for root from 203.0.113.99 port 49999 ssh2\n")

        result = run_monitor(directory, executable=True)
        assert result.returncode == 0, f"Script failed on generated corpus. Stderr: {result.stderr}"
        actual = parsed_output(result.stdout)
        expected = {(label, filename) for filename, (label, _) in cases.items()}

        assert len(actual) == len(cases), \
            f"Expected exactly one classification per .log file; got: {result.stdout!r}"
        assert set(actual) == expected, \
            f"Generated logs were classified incorrectly. Expected {expected}, got {set(actual)}"


def test_cli_requires_exactly_one_directory_argument():
    no_args = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True, timeout=10)
    assert no_args.returncode != 0, "CLI unexpectedly accepted no directory argument"

    with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
        too_many = subprocess.run(
            ["python3", SCRIPT_PATH, first, second], capture_output=True, text=True, timeout=10
        )
    assert too_many.returncode != 0, "CLI unexpectedly accepted more than one positional argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
