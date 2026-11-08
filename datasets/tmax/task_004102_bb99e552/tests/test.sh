#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re


def parse_systemd(path):
    sections = {}
    current = None
    with open(path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            match = re.fullmatch(r"\[([^]]+)\]", line)
            if match:
                current = match.group(1)
                sections.setdefault(current, [])
                continue
            if current is not None and "=" in line:
                key, value = line.split("=", 1)
                sections[current].append((key.strip(), value.strip()))
    return sections


def tokenize_nginx(path):
    with open(path, "r") as f:
        content = f.read()

    tokens = []
    token = []
    quote = None
    escaped = False
    i = 0
    while i < len(content):
        char = content[i]
        if quote is not None:
            if escaped:
                token.append(char)
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            else:
                token.append(char)
            i += 1
            continue

        if char in ("'", '"'):
            quote = char
        elif char == "#":
            if token:
                tokens.append("".join(token))
                token = []
            while i < len(content) and content[i] != "\n":
                i += 1
            continue
        elif char.isspace():
            if token:
                tokens.append("".join(token))
                token = []
        elif char in "{};":
            if token:
                tokens.append("".join(token))
                token = []
            tokens.append(char)
        else:
            token.append(char)
        i += 1

    if token:
        tokens.append("".join(token))
    assert quote is None, "Unterminated quoted string in nginx.conf"
    return tokens


def parse_nginx_directives(path):
    directives = []
    contexts = []
    pending = []

    for token in tokenize_nginx(path):
        if token == "{":
            assert pending, "Nginx block without a header"
            contexts.append(tuple(pending))
            pending = []
        elif token == ";":
            assert pending, "Empty nginx directive"
            directives.append((tuple(contexts), tuple(pending)))
            pending = []
        elif token == "}":
            assert not pending, "Nginx directive missing semicolon"
            assert contexts, "Unmatched closing brace in nginx.conf"
            contexts.pop()
        else:
            pending.append(token)

    assert not pending, "Incomplete nginx directive"
    assert not contexts, "Unclosed block in nginx.conf"
    return directives


def test_nginx_service_after():
    path = "/home/user/.config/systemd/user/nginx.service"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original textual assertion.
    assert re.search(r"^After\s*=\s*api\.service", content, re.MULTILINE), \
        f"Missing or incorrect 'After=api.service' directive in {path}"

    sections = parse_systemd(path)
    unit_after_values = [value for key, value in sections.get("Unit", []) if key == "After"]
    assert any("api.service" in value.split() for value in unit_after_values), \
        f"An active After= directive for api.service is not present in [Unit] in {path}"


def test_api_service_environment_file():
    path = "/home/user/.config/systemd/user/api.service"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original textual assertion.
    assert re.search(r"^EnvironmentFile\s*=\s*/home/user/app\.env", content, re.MULTILINE), \
        f"Missing or incorrect 'EnvironmentFile=/home/user/app.env' directive in {path}"

    sections = parse_systemd(path)
    service_values = [value for key, value in sections.get("Service", [])
                      if key == "EnvironmentFile"]
    assert "/home/user/app.env" in service_values, \
        f"An active EnvironmentFile=/home/user/app.env directive is not present in [Service] in {path}"


def test_nginx_conf_proxy_pass():
    path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original textual assertion.
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8000\s*;", content), \
        f"proxy_pass is not correctly set to http://127.0.0.1:8000; in {path}"

    directives = parse_nginx_directives(path)
    proxy_directives = [(contexts, directive) for contexts, directive in directives
                        if directive and directive[0] == "proxy_pass"]
    assert len(proxy_directives) == 1, \
        f"Expected exactly one active proxy_pass directive in {path}, found {len(proxy_directives)}"

    contexts, directive = proxy_directives[0]
    assert directive == ("proxy_pass", "http://127.0.0.1:8000"), \
        f"Active proxy_pass is not exactly http://127.0.0.1:8000 in {path}"
    assert any(ctx == ("http",) for ctx in contexts), \
        "proxy_pass is not inside the http block"
    assert any(ctx and ctx[0] == "server" for ctx in contexts), \
        "proxy_pass is not inside a server block"
    assert any(ctx and ctx[0] == "location" and ctx[-1] == "/" for ctx in contexts), \
        "proxy_pass is not inside the location / block"


def test_app_public_symlink():
    link_path = "/home/user/app/public"
    target_path = "/home/user/shared_public"

    assert os.path.islink(link_path), f"Path {link_path} is not a symbolic link"

    actual_target = os.readlink(link_path)
    assert actual_target == target_path, \
        f"Symlink {link_path} points to {actual_target} instead of {target_path}"


def test_502_ips_extracted():
    log_path = "/home/user/logs/nginx_access.log"
    output_path = "/home/user/502_ips.txt"

    assert os.path.isfile(log_path), f"Original log file missing: {log_path}"
    assert os.path.isfile(output_path), f"Output file missing: {output_path}"

    expected_ips = set()
    with open(log_path, "r") as f:
        for line in f:
            parts = line.split()
            if len(parts) > 8 and parts[8] == "502":
                expected_ips.add(parts[0])

    actual_ips = set()
    with open(output_path, "r") as f:
        for line in f:
            ip = line.strip()
            if ip:
                actual_ips.add(ip)

    assert actual_ips == expected_ips, \
        f"Extracted IPs {actual_ips} do not match the expected 502 IPs {expected_ips}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
