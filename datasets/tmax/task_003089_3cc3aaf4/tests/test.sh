#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import stat
import subprocess


def nonempty_raw_lines(path):
    with open(path, "r") as f:
        return [line for line in f.read().splitlines() if line != ""]


def test_manifests_directory_empty():
    path = "/home/user/manifests"
    assert os.path.isdir(path), f"Directory {path} should exist."
    files = os.listdir(path)
    assert len(files) == 0, f"Directory {path} should be empty, but contains {files}."


def test_processed_manifests_files_and_permissions():
    path_alpha = "/home/user/processed_manifests/cluster-alpha.yaml"
    path_beta = "/home/user/processed_manifests/cluster-beta.yaml"

    assert os.path.isfile(path_alpha), f"File {path_alpha} is missing."
    assert os.path.isfile(path_beta), f"File {path_beta} is missing."

    mode_alpha = stat.S_IMODE(os.stat(path_alpha).st_mode)
    assert mode_alpha == 0o400, f"File {path_alpha} has incorrect permissions: {oct(mode_alpha)}, expected 0o400."

    mode_beta = stat.S_IMODE(os.stat(path_beta).st_mode)
    assert mode_beta == 0o400, f"File {path_beta} has incorrect permissions: {oct(mode_beta)}, expected 0o400."


def test_apply_routes_script():
    path = "/home/user/apply_routes.sh"
    assert os.path.isfile(path), f"File {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

    content = [line.strip() for line in nonempty_raw_lines(path)]
    expected_lines = [
        "ip route add 10.244.0.0/16 via 10.96.0.1",
        "ip route add 192.168.50.0/24 via 10.96.0.1",
    ]

    for expected in expected_lines:
        assert any(expected in line for line in content), f"Expected command '{expected}' not found in {path}."
        assert expected in nonempty_raw_lines(path), f"Expected exact command '{expected}' not found in {path}."


def test_operator_log():
    path = "/home/user/operator.log"
    assert os.path.isfile(path), f"File {path} is missing."

    content = [line.strip() for line in nonempty_raw_lines(path)]
    expected_lines = [
        "PROCESSED cluster-alpha.yaml 10.244.0.0/16",
        "PROCESSED cluster-beta.yaml 192.168.50.0/24",
    ]

    for expected in expected_lines:
        assert any(expected in line for line in content), f"Expected log entry '{expected}' not found in {path}."
        assert expected in nonempty_raw_lines(path), f"Expected exact log entry '{expected}' not found in {path}."


def test_k8s_operator_script_exists():
    path = "/home/user/k8s-operator.sh"
    assert os.path.isfile(path), f"File {path} is missing. The script must be saved here."


def test_operator_processes_fresh_manifests_functionally():
    operator = "/home/user/k8s-operator.sh"
    manifests = "/home/user/manifests"
    processed = "/home/user/processed_manifests"
    routes = "/home/user/apply_routes.sh"
    log = "/home/user/operator.log"

    before_routes = nonempty_raw_lines(routes)
    before_log = nonempty_raw_lines(log)

    token = secrets.token_hex(6)
    octets = secrets.token_bytes(6)
    entries = [
        (f"probe-a-{token}.yaml", f"172.{16 + octets[0] % 16}.{octets[1]}.0/24"),
        (f"probe-b-{token}.yaml", f"172.{32 + octets[2] % 16}.{octets[3]}.0/24"),
        (f"probe-c-{token}.yaml", f"172.{48 + octets[4] % 16}.{octets[5]}.0/24"),
    ]

    user = pwd.getpwnam("user")
    original_contents = {}
    for filename, cidr in reversed(entries):
        data = (
            "apiVersion: custom.k8s.io/v1\n"
            "kind: ClusterNetwork\n"
            "metadata:\n"
            f"  name: {filename[:-5]}\n"
            "spec:\n"
            f"  podCIDR: {cidr}\n"
            "  gateway: 10.96.0.1\n"
        ).encode()
        source = os.path.join(manifests, filename)
        with open(source, "wb") as f:
            f.write(data)
        os.chown(source, user.pw_uid, user.pw_gid)
        original_contents[filename] = data

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", operator],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Operator failed: stdout={result.stdout!r}, stderr={result.stderr!r}"

    assert os.listdir(manifests) == [], f"Incoming directory was not emptied: {os.listdir(manifests)}"

    for filename, _ in entries:
        destination = os.path.join(processed, filename)
        assert os.path.isfile(destination), f"Processed manifest {destination} is missing."
        with open(destination, "rb") as f:
            assert f.read() == original_contents[filename], f"Manifest {filename} was not moved intact."
        mode = stat.S_IMODE(os.stat(destination).st_mode)
        assert mode == 0o400, f"File {destination} has mode {oct(mode)}, expected 0o400."

    expected_routes = [f"ip route add {cidr} via 10.96.0.1" for _, cidr in entries]
    expected_log = [f"PROCESSED {filename} {cidr}" for filename, cidr in entries]
    assert nonempty_raw_lines(routes) == before_routes + expected_routes, "Routes were not appended exactly in filename order."
    assert nonempty_raw_lines(log) == before_log + expected_log, "Log entries were not appended exactly in filename order."
    assert os.path.isfile(routes), f"File {routes} is missing."
    assert os.access(routes, os.X_OK), f"File {routes} is not executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
