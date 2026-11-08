#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import ipaddress
import json
import os
import random
import secrets
import shlex
import shutil
import subprocess
import tempfile


def run_filter(binary_path, args, cwd=None):
    try:
        return subprocess.run(
            [binary_path] + args,
            cwd=cwd,
            capture_output=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"Filter timed out for arguments: {args}")


def test_setup_ci_script():
    setup_script = "/home/user/setup_ci.sh"
    assert os.path.isfile(setup_script), f"Setup script {setup_script} does not exist."

    # Execute the setup script
    result = subprocess.run(["bash", setup_script], capture_output=True, text=True)
    assert result.returncode == 0, f"Setup script failed with exit code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"


def test_filter_binary_exists():
    binary_path = "/home/user/netfilter/filter"
    assert os.path.isfile(binary_path), f"Binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."


def test_systemd_service_file():
    service_path = "/home/user/netfilter.service"
    assert os.path.isfile(service_path), f"Service file {service_path} does not exist."

    with open(service_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "[Unit]" in content, f"Service file {service_path} is missing [Unit] section."
    assert "[Service]" in content, f"Service file {service_path} is missing [Service] section."
    assert "ExecStart" in content, f"Service file {service_path} is missing ExecStart directive."

    # Ensure ExecStart is an active directive in [Service], not merely a comment or keyword.
    section = None
    exec_values = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line
            continue
        if section == "[Service]" and "=" in line:
            key, value = line.split("=", 1)
            if key.strip() == "ExecStart":
                exec_values.append(value.strip())

    assert exec_values, "Service file has no active ExecStart directive in [Service]."
    command = exec_values[-1]
    if command.startswith("-"):
        command = command[1:].lstrip()
    argv = shlex.split(command)
    assert argv and argv[0] == "/home/user/netfilter/filter", \
        "ExecStart must execute /home/user/netfilter/filter."

    analyzer = shutil.which("systemd-analyze")
    if analyzer:
        result = subprocess.run([analyzer, "verify", service_path], capture_output=True, text=True)
        assert result.returncode == 0, \
            f"Invalid systemd unit.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"


def test_adversarial_corpus_filtering():
    binary_path = "/home/user/netfilter/filter"
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failures = []
    for f in clean_files:
        result = subprocess.run([binary_path, f], capture_output=True)
        if result.returncode != 0:
            clean_failures.append(os.path.basename(f))

    evil_failures = []
    for f in evil_files:
        result = subprocess.run([binary_path, f], capture_output=True)
        if result.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures[:10])}")
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures[:10])}")

    assert not clean_failures and not evil_failures, "Corpus filtering failed:\n" + "\n".join(error_msgs)


def test_filter_on_unseen_generated_requests():
    binary_path = "/home/user/netfilter/filter"
    blocked_network = ipaddress.ip_network("10.42.0.0/16")

    explicit = [
        ("10.42.0.0", 8080),
        ("10.42.0.255", 8080),
        ("10.42.1.1", 8080),
        ("10.42.128.9", 8080),
        ("10.42.255.255", 8080),
        ("10.42.0.1", 8079),
        ("10.42.200.10", 8081),
        ("10.41.255.255", 8080),
        ("10.43.0.0", 8080),
        ("192.0.2.44", 8080),
    ]

    generated = list(explicit)
    for _ in range(50):
        address = ipaddress.IPv4Address(secrets.randbits(32))
        port = random.choice([1, 80, 443, 8079, 8080, 8081, 65535])
        generated.append((str(address), port))

    # Add unpredictable addresses from throughout the blocked /16, not just 10.42.0.x.
    for _ in range(20):
        host = secrets.randbelow(1 << 16)
        address = ipaddress.IPv4Address(int(blocked_network.network_address) + host)
        generated.append((str(address), random.choice([8080, 8080, 8080, 8079, 8081])))

    random.shuffle(generated)
    with tempfile.TemporaryDirectory(prefix="netfilter-unseen-") as temp_dir:
        failures = []
        for src_ip, dst_port in generated:
            request = {
                "src_ip": src_ip,
                "dst_port": dst_port,
                "protocol": secrets.choice(["tcp", "udp", "other"]),
                "payload": secrets.token_hex(12),
            }
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".data")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(request, handle)

            expected = 1 if ipaddress.ip_address(src_ip) in blocked_network and dst_port == 8080 else 0
            result = run_filter(binary_path, [path])
            if result.returncode != expected:
                failures.append((src_ip, dst_port, expected, result.returncode))

        assert not failures, f"Incorrect results for unseen requests: {failures[:10]}"


def test_invalid_paths_arguments_and_malformed_json():
    binary_path = "/home/user/netfilter/filter"
    with tempfile.TemporaryDirectory(prefix="netfilter-invalid-") as temp_dir:
        missing = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
        assert run_filter(binary_path, [missing]).returncode == 1, \
            "A nonexistent absolute path must exit 1."
        assert run_filter(binary_path, [temp_dir]).returncode == 1, \
            "A directory path must exit 1."
        assert run_filter(binary_path, []).returncode == 1, \
            "Calling the filter without a path must exit 1."

        valid_name = secrets.token_hex(10) + ".json"
        valid_path = os.path.join(temp_dir, valid_name)
        with open(valid_path, "w", encoding="utf-8") as handle:
            json.dump({"src_ip": "192.0.2.1", "dst_port": 80, "protocol": "tcp", "payload": "x"}, handle)
        assert run_filter(binary_path, [valid_name], cwd=temp_dir).returncode == 1, \
            "A relative input path must be rejected."
        assert run_filter(binary_path, [valid_path, valid_path]).returncode == 1, \
            "The filter must reject more than one command-line argument."

        malformed_documents = [
            "",
            "not json",
            '{"src_ip":"10.42.1.2","dst_port":8080',
            '{"src_ip":"10.42.1.2",,"dst_port":8080}',
        ]
        for document in malformed_documents:
            path = os.path.join(temp_dir, secrets.token_hex(12) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(document)
            assert run_filter(binary_path, [path]).returncode == 1, \
                f"Malformed JSON did not exit 1: {document!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
