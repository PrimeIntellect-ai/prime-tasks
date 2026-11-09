#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ipaddress
import json
import os
import secrets
import subprocess
import tempfile

import pytest

CLASSIFIER_SCRIPT = "/home/user/classifier.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
AVAILABLE_RULES = "/home/user/configs/available/network_rules.json"
ENABLED_SYMLINK = "/home/user/configs/enabled/active.json"
SYSTEMD_SERVICE = "/home/user/.config/systemd/user/log-analyzer.service"

EXPECTED_SUBNET = ipaddress.ip_network("172.16.0.0/12")
EXPECTED_RESTRICTED_PORT = 8080
EXPECTED_QUOTA_MB = 500.0


def run_classifier(path, *extra_args):
    return subprocess.run(
        ["/usr/bin/python3", CLASSIFIER_SCRIPT, path, *extra_args],
        capture_output=True,
        text=True,
        timeout=5,
    )


def expected_result(record):
    source = ipaddress.ip_address(record["source_ip"])
    clean = (
        source in EXPECTED_SUBNET
        and record["dest_port"] != EXPECTED_RESTRICTED_PORT
        and record["log_size_mb"] <= EXPECTED_QUOTA_MB
    )
    return 0 if clean else 1


def random_inside_ip():
    offset = 1 + secrets.randbelow(EXPECTED_SUBNET.num_addresses - 2)
    return str(EXPECTED_SUBNET.network_address + offset)


def random_outside_ip():
    while True:
        candidate = ipaddress.IPv4Address(secrets.randbits(32))
        if candidate not in EXPECTED_SUBNET:
            return str(candidate)


def random_allowed_port():
    while True:
        port = 1 + secrets.randbelow(65535)
        if port != EXPECTED_RESTRICTED_PORT:
            return port


def test_classifier_script_exists():
    assert os.path.isfile(CLASSIFIER_SCRIPT), f"Classifier script not found at {CLASSIFIER_SCRIPT}"


def test_adversarial_corpus_clean():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus dir missing: {CLEAN_CORPUS_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".json")]
    assert clean_files, "No clean corpus files found."

    failed_clean = []
    for name in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, name)
        if run_classifier(filepath).returncode != 0:
            failed_clean.append(name)

    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}"


def test_adversarial_corpus_evil():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus dir missing: {EVIL_CORPUS_DIR}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".json")]
    assert evil_files, "No evil corpus files found."

    bypassed_evil = []
    for name in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, name)
        if run_classifier(filepath).returncode != 1:
            bypassed_evil.append(name)

    assert not bypassed_evil, f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}"


def test_generated_independent_rule_cases():
    records = [
        {"source_ip": "172.16.0.1", "dest_port": 443, "log_size_mb": 500.0},
        {"source_ip": "172.31.255.254", "dest_port": 53, "log_size_mb": 499.999999},
        {"source_ip": "172.15.255.255", "dest_port": 443, "log_size_mb": 100.0},
        {"source_ip": "172.32.0.1", "dest_port": 443, "log_size_mb": 100.0},
        {"source_ip": "172.20.10.5", "dest_port": 8080, "log_size_mb": 100.0},
        {"source_ip": "172.20.10.5", "dest_port": 443, "log_size_mb": 500.000001},
    ]

    for _ in range(12):
        inside = random_inside_ip()
        outside = random_outside_ip()
        port = random_allowed_port()
        size = secrets.randbelow(500000) / 1000.0
        records.extend([
            {"source_ip": inside, "dest_port": port, "log_size_mb": size},
            {"source_ip": outside, "dest_port": port, "log_size_mb": size},
            {"source_ip": inside, "dest_port": EXPECTED_RESTRICTED_PORT, "log_size_mb": size},
            {"source_ip": inside, "dest_port": port, "log_size_mb": EXPECTED_QUOTA_MB + 1 + secrets.randbelow(1000) / 10.0},
        ])

    with tempfile.TemporaryDirectory(prefix="classifier-check-") as directory:
        for index, record in enumerate(records):
            path = os.path.join(directory, f"{secrets.token_hex(12)}.json")
            with open(path, "w", encoding="utf-8") as handle:
                if index % 3 == 0:
                    json.dump(record, handle, indent=2, sort_keys=True)
                elif index % 3 == 1:
                    json.dump({key: record[key] for key in reversed(record)}, handle)
                else:
                    json.dump(record, handle, separators=(",", ":"))

            result = run_classifier(path)
            expected = expected_result(record)
            assert result.returncode == expected, (
                f"Classifier returned {result.returncode}, expected {expected} for {record}. "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )


def test_classifier_requires_exactly_one_argument():
    no_argument = subprocess.run(
        ["/usr/bin/python3", CLASSIFIER_SCRIPT],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert no_argument.returncode != 0, "Classifier accepted no input argument"

    with tempfile.TemporaryDirectory(prefix="classifier-args-") as directory:
        first = os.path.join(directory, f"{secrets.token_hex(8)}.json")
        second = os.path.join(directory, f"{secrets.token_hex(8)}.json")
        record = {"source_ip": random_inside_ip(), "dest_port": 443, "log_size_mb": 1.0}
        for path in (first, second):
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(record, handle)
        too_many = run_classifier(first, second)
        assert too_many.returncode != 0, "Classifier accepted more than one input argument"


def test_network_rules_json():
    assert os.path.isfile(AVAILABLE_RULES), f"Rules JSON not found at {AVAILABLE_RULES}"
    with open(AVAILABLE_RULES, "r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {AVAILABLE_RULES} is not valid JSON.")

    subnet = data.get("subnet")
    restricted_port = data.get("restricted_port")
    quota_mb = data.get("quota_mb")

    assert subnet == "172.16.0.0/12", f"Expected subnet '172.16.0.0/12', got {subnet}"
    assert str(restricted_port) == "8080", f"Expected restricted_port 8080, got {restricted_port}"
    assert float(quota_mb) == 500.0, f"Expected quota_mb 500.0, got {quota_mb}"


def test_enabled_symlink():
    assert os.path.islink(ENABLED_SYMLINK), f"Symlink not found at {ENABLED_SYMLINK}"
    target = os.readlink(ENABLED_SYMLINK)
    assert target == AVAILABLE_RULES, f"Symlink points to {target}, expected {AVAILABLE_RULES}"


def test_systemd_service_file():
    assert os.path.isfile(SYSTEMD_SERVICE), f"Systemd service file not found at {SYSTEMD_SERVICE}"
    with open(SYSTEMD_SERVICE, "r", encoding="utf-8") as handle:
        content = handle.read()

    expected_exec_start = "ExecStart=/usr/bin/python3 /home/user/classifier.py /home/user/configs/enabled/active.json"
    assert expected_exec_start in content, f"Expected ExecStart line not found in {SYSTEMD_SERVICE}"

    section = None
    service_exec_starts = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
        elif section == "Service" and line.startswith("ExecStart="):
            service_exec_starts.append(line)

    assert "Service" in [line.strip()[1:-1].strip() for line in content.splitlines() if line.strip().startswith("[") and line.strip().endswith("]")], "Missing [Service] section"
    assert expected_exec_start in service_exec_starts, "Required ExecStart is not an active directive in [Service]"

    verified = subprocess.run(
        ["systemd-analyze", "verify", SYSTEMD_SERVICE],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert verified.returncode == 0, (
        f"Service is not a valid systemd unit. stdout: {verified.stdout.strip()}, "
        f"stderr: {verified.stderr.strip()}"
    )


def test_systemd_service_enabled():
    uid = subprocess.check_output(["id", "-u", "user"], text=True).strip()
    env_args = [
        "HOME=/home/user",
        "USER=user",
        "LOGNAME=user",
        "XDG_CONFIG_HOME=/home/user/.config",
        f"XDG_RUNTIME_DIR=/run/user/{uid}",
    ]
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", *env_args,
         "systemctl", "--user", "is-enabled", "log-analyzer.service"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.stdout.strip() == "enabled", (
        f"Service is not enabled for user. stdout: {result.stdout.strip()}, "
        f"stderr: {result.stderr.strip()}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
