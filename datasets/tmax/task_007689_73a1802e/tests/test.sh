#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import stat
import subprocess

import pytest

SCRIPT_PATH = "/home/user/deploy_edge.py"
ENV_DIR = "/home/user/iot_env"
NGINX_CONF = os.path.join(ENV_DIR, "nginx.conf")
LOGROTATE_CONF = os.path.join(ENV_DIR, "logrotate.conf")
MANIFEST_JSON = os.path.join(ENV_DIR, "manifest.json")
FIXED_PORTS = [8081, 8082, 8083]


def run_script(ports):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, "--backends", ",".join(map(str, ports))],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script failed for ports {ports}: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )


def snapshot_tree(path):
    """Capture the complete content/type/permission state beneath path."""
    assert os.path.isdir(path) and not os.path.islink(path)
    snapshot = {}

    def visit(current, relative):
        info = os.lstat(current)
        metadata = (stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid)
        if stat.S_ISDIR(info.st_mode):
            snapshot[relative] = ("dir", metadata)
            for name in sorted(os.listdir(current)):
                child_rel = os.path.join(relative, name) if relative else name
                visit(os.path.join(current, name), child_rel)
        elif stat.S_ISREG(info.st_mode):
            with open(current, "rb") as handle:
                snapshot[relative] = ("file", metadata, handle.read())
        elif stat.S_ISLNK(info.st_mode):
            snapshot[relative] = ("symlink", metadata, os.readlink(current))
        else:
            snapshot[relative] = ("other", metadata, info.st_mode)

    visit(path, "")
    return snapshot


def tokenize_nginx(content):
    tokens = []
    index = 0
    while index < len(content):
        char = content[index]
        if char.isspace():
            index += 1
            continue
        if char == "#":
            newline = content.find("\n", index)
            index = len(content) if newline == -1 else newline + 1
            continue
        if char in "{};":
            tokens.append(char)
            index += 1
            continue
        if char in "\"'":
            quote = char
            index += 1
            value = []
            while index < len(content) and content[index] != quote:
                if content[index] == "\\" and index + 1 < len(content):
                    index += 1
                value.append(content[index])
                index += 1
            assert index < len(content), "Unterminated quoted string in nginx.conf"
            index += 1
            tokens.append("".join(value))
            continue

        start = index
        while index < len(content) and not content[index].isspace() and content[index] not in "{};#":
            index += 1
        tokens.append(content[start:index])
    return tokens


def parse_nginx(content):
    tokens = tokenize_nginx(content)
    position = 0

    def parse_level(needs_closing_brace):
        nonlocal position
        nodes = []
        while position < len(tokens):
            if tokens[position] == "}":
                assert needs_closing_brace, "Unexpected closing brace in nginx.conf"
                position += 1
                return nodes

            arguments = []
            while position < len(tokens) and tokens[position] not in ("{", "}", ";"):
                arguments.append(tokens[position])
                position += 1
            assert arguments, "Empty or malformed nginx directive"
            assert position < len(tokens), "Nginx directive is missing ';' or a block"

            delimiter = tokens[position]
            position += 1
            if delimiter == ";":
                nodes.append((arguments, None))
            elif delimiter == "{":
                nodes.append((arguments, parse_level(True)))
            else:
                pytest.fail("Nginx directive ended at an unexpected closing brace")

        assert not needs_closing_brace, "Unclosed block in nginx.conf"
        return nodes

    parsed = parse_level(False)
    assert position == len(tokens), "Trailing malformed nginx syntax"
    return parsed


def direct_blocks(nodes, name):
    return [node for node in nodes if node[1] is not None and node[0] == [name]]


def direct_directives(nodes, name):
    return [node[0] for node in nodes if node[1] is None and node[0] and node[0][0] == name]


def validate_nginx(expected_ports):
    assert os.path.isfile(NGINX_CONF), f"Nginx config not found at {NGINX_CONF}"
    with open(NGINX_CONF, "r", encoding="utf-8") as handle:
        content = handle.read()

    # Preserve the original verifier's assertions.
    assert "upstream backend_cluster" in content, "Missing 'upstream backend_cluster' block in nginx.conf"
    assert "listen 8080" in content.replace(";", ""), "Missing 'listen 8080' in nginx.conf"
    assert "proxy_pass http://backend_cluster;" in content, "Missing 'proxy_pass http://backend_cluster;' in nginx.conf"
    assert "access_log /home/user/iot_env/access.log;" in content, "Missing 'access_log /home/user/iot_env/access.log;' in nginx.conf"
    for port in expected_ports:
        server_line = f"server 127.0.0.1:{port};"
        assert server_line in content, f"Missing '{server_line}' in nginx.conf"
        assert content.count(server_line) == 1, f"Duplicate '{server_line}' found in nginx.conf. Script is not idempotent."

    parsed = parse_nginx(content)
    events_blocks = direct_blocks(parsed, "events")
    http_blocks = direct_blocks(parsed, "http")
    assert len(events_blocks) == 1, "A valid standalone nginx.conf must contain one top-level events block"
    assert len(http_blocks) == 1, "A valid standalone nginx.conf must contain one top-level http block"
    http_children = http_blocks[0][1]

    upstreams = [
        node for node in http_children
        if node[1] is not None and node[0] == ["upstream", "backend_cluster"]
    ]
    assert len(upstreams) == 1, "Expected exactly one upstream backend_cluster block"
    backend_directives = direct_directives(upstreams[0][1], "server")
    expected_backend_directives = [
        ["server", f"127.0.0.1:{port}"] for port in expected_ports
    ]
    assert backend_directives == expected_backend_directives, (
        "backend_cluster must contain exactly one server directive per requested port, in input order"
    )

    frontend_servers = [
        node for node in http_children if node[1] is not None and node[0] == ["server"]
    ]
    assert len(frontend_servers) == 1, "Expected exactly one reverse-proxy server block"
    server_children = frontend_servers[0][1]
    assert direct_directives(server_children, "listen") == [["listen", "8080"]], (
        "The reverse-proxy server must contain exactly 'listen 8080;'"
    )
    assert direct_directives(server_children, "access_log") == [
        ["access_log", "/home/user/iot_env/access.log"]
    ], "The server must contain exactly the required access_log directive"

    locations = [
        node for node in server_children
        if node[1] is not None and node[0] == ["location", "/"]
    ]
    assert len(locations) == 1, "Expected exactly one 'location /' block"
    assert direct_directives(locations[0][1], "proxy_pass") == [
        ["proxy_pass", "http://backend_cluster"]
    ], "location / must contain exactly the required proxy_pass directive"


def validate_logrotate():
    assert os.path.isfile(LOGROTATE_CONF), f"Logrotate config not found at {LOGROTATE_CONF}"
    with open(LOGROTATE_CONF, "r", encoding="utf-8") as handle:
        content = handle.read()

    # Preserve the original verifier's assertions.
    assert "/home/user/iot_env/access.log" in content, "Target log file not specified in logrotate.conf"
    directives = ["daily", "rotate 7", "compress", "missingok", "notifempty"]
    for directive in directives:
        assert directive in content, f"Missing directive '{directive}' in logrotate.conf"

    lines = []
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if line:
            lines.append(line)

    target = "/home/user/iot_env/access.log"
    assert lines, "logrotate.conf is empty"
    normalized_first = re.sub(r"\s+", " ", lines[0])
    if normalized_first == target:
        assert len(lines) >= 2 and lines[1] == "{", "Missing opening logrotate block brace"
        body_start = 2
    else:
        assert normalized_first == target + " {", "Logrotate block must target only access.log"
        body_start = 1
    assert lines[-1] == "}", "Missing closing logrotate block brace"
    body = [re.sub(r"\s+", " ", line) for line in lines[body_start:-1]]
    assert body == directives, (
        "The access.log block must contain exactly daily, rotate 7, compress, missingok, and notifempty"
    )


def validate_manifest(expected_ports):
    assert os.path.isfile(MANIFEST_JSON), f"Manifest JSON not found at {MANIFEST_JSON}"
    with open(MANIFEST_JSON, "r", encoding="utf-8") as handle:
        try:
            manifest = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail("manifest.json is not valid JSON")

    # Preserve the original semantic assertions and enforce the exact structure.
    assert manifest.get("status") == "success", "Manifest status should be 'success'"
    assert manifest.get("deployed_backends") == expected_ports, "Manifest deployed_backends does not match expected integer list"
    assert manifest == {
        "deployed_backends": expected_ports,
        "status": "success",
    }, "manifest.json must have exactly the required structure"


def validate_artifacts(expected_ports):
    assert os.path.isdir(ENV_DIR), f"Target directory {ENV_DIR} was not created."
    validate_nginx(expected_ports)
    validate_logrotate()
    validate_manifest(expected_ports)


@pytest.fixture(scope="module", autouse=True)
def run_student_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), "Submission must be a regular Python file"

    if os.path.lexists(ENV_DIR):
        if os.path.isdir(ENV_DIR) and not os.path.islink(ENV_DIR):
            shutil.rmtree(ENV_DIR)
        else:
            os.unlink(ENV_DIR)

    generator = secrets.SystemRandom()
    dynamic_ports = generator.sample(range(12000, 50000), 4)
    while any(port in FIXED_PORTS for port in dynamic_ports):
        dynamic_ports = generator.sample(range(12000, 50000), 4)

    # Exercise CLI parsing and derive all expected output from unpredictable inputs.
    run_script(dynamic_ports)
    validate_artifacts(dynamic_ports)
    first_state = snapshot_tree(ENV_DIR)
    run_script(dynamic_ports)
    validate_artifacts(dynamic_ports)
    assert snapshot_tree(ENV_DIR) == first_state, (
        "Running twice with the same arguments changed the target directory state"
    )

    changed_ports = list(reversed(dynamic_ports[:2]))
    run_script(changed_ports)
    validate_artifacts(changed_ports)
    changed_state = snapshot_tree(ENV_DIR)
    run_script(changed_ports)
    validate_artifacts(changed_ports)
    assert snapshot_tree(ENV_DIR) == changed_state, (
        "Idempotency failed for a second backend list"
    )

    # Retain the original fixed-input rerun and leave that state for the original tests.
    run_script(FIXED_PORTS)
    fixed_state = snapshot_tree(ENV_DIR)
    run_script(FIXED_PORTS)
    assert snapshot_tree(ENV_DIR) == fixed_state, (
        "Running twice with the original arguments changed the target directory state"
    )


def test_env_directory_exists():
    assert os.path.isdir(ENV_DIR), f"Target directory {ENV_DIR} was not created."


def test_nginx_conf():
    validate_nginx(FIXED_PORTS)


def test_logrotate_conf():
    validate_logrotate()


def test_manifest_json():
    validate_manifest(FIXED_PORTS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
