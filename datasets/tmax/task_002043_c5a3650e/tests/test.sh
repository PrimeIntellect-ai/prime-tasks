#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

INFRA = Path("/home/user/infra")
SCRIPT = Path("/home/user/harden.py")
EXPECTED_IPS = set()


def random_ip():
    return f"10.{secrets.randbelow(250) + 1}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}"


def prepare_and_run_submission():
    assert SCRIPT.is_file(), "/home/user/harden.py does not exist or is not a regular file"
    assert SCRIPT.stat().st_size > 0, "/home/user/harden.py is empty"

    compile_result = subprocess.run(
        ["python3", "-m", "py_compile", str(SCRIPT)],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    if INFRA.exists():
        shutil.rmtree(INFRA)
    INFRA.mkdir(parents=True)

    (INFRA / "ssh_config").write_text(
        "Host *\n"
        "    PasswordAuthentication yes\n"
        "    IdentityFile ~/.ssh/id_rsa\n"
    )
    (INFRA / "nginx.conf").write_text(
        "server {\n"
        "    listen 80;\n"
        "    server_name example.com;\n"
        "    location / {\n"
        "        root /var/www/html;\n"
        "    }\n"
        "}\n"
    )

    ips = set()
    while len(ips) < 8:
        ips.add(random_ip())
    ips = list(ips)
    malicious = set(ips[:5])
    global EXPECTED_IPS
    EXPECTED_IPS = malicious

    lines = [
        f'{ips[5]} - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326',
        f'{ips[0]} - - [10/Oct/2023:13:56:10 -0700] "GET /../../../../etc/passwd HTTP/1.1" 403 512',
        f'{ips[6]} - - [10/Oct/2023:13:57:00 -0700] "GET /about.html HTTP/1.1" 200 1024',
        f'{ips[1]} - - [10/Oct/2023:13:58:22 -0700] "GET /images/%2e%2e%2f%2e%2e%2fetc/shadow HTTP/1.1" 403 512',
        f'{ips[2]} - - [10/Oct/2023:14:00:15 -0700] "GET /api/v1/data?file=../config.json HTTP/1.1" 403 512',
        f'{ips[7]} - - [10/Oct/2023:14:02:45 -0700] "GET /static/css/style.css HTTP/1.1" 200 3200',
        f'{ips[3]} - - [10/Oct/2023:14:03:10 -0700] "GET /download?path=%2E%2E%2F%2e%2e%2fetc/hosts HTTP/1.1" 403 512',
        f'{ips[4]} - - [10/Oct/2023:14:04:05 -0700] "GET /uploads/../.env HTTP/1.1" 403 512',
    ]
    (INFRA / "access.log").write_text("\n".join(lines) + "\n")

    result = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"harden.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


prepare_and_run_submission()


def get_true_malicious_ips():
    content = (INFRA / "access.log").read_text()
    malicious_ips = set()
    for line in content.splitlines():
        if "../" in line or "%2e%2e%2f" in line.lower():
            parts = line.split()
            if parts:
                malicious_ips.add(parts[0])
    return malicious_ips


def read_predicted_ips():
    path = INFRA / "banned_ips.txt"
    if not path.is_file():
        return set()
    return {line.strip() for line in path.read_text().splitlines() if line.strip()}


def nginx_tokens(text):
    cleaned = []
    for line in text.splitlines():
        quote = None
        escaped = False
        out = []
        for ch in line:
            if escaped:
                out.append(ch)
                escaped = False
                continue
            if ch == "\\" and quote:
                out.append(ch)
                escaped = True
                continue
            if ch in ("'", '"'):
                if quote == ch:
                    quote = None
                elif quote is None:
                    quote = ch
                out.append(ch)
                continue
            if ch == "#" and quote is None:
                break
            out.append(ch)
        cleaned.append("".join(out))

    pattern = re.compile(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[{};]|[^\s{};'\"]+''')
    result = []
    for token in pattern.findall("\n".join(cleaned)):
        if len(token) >= 2 and token[0] == token[-1] and token[0] in ("'", '"'):
            token = token[1:-1]
        result.append(token)
    return result


def server_blocks(text):
    stack = []
    servers = []
    pending = []
    for token in nginx_tokens(text):
        if token == "{":
            kind = pending[0].lower() if pending else ""
            context = {"kind": kind, "directives": []}
            stack.append(context)
            if kind == "server":
                servers.append(context)
            pending = []
        elif token == ";":
            if stack and stack[-1]["kind"] == "server" and pending:
                stack[-1]["directives"].append(pending)
            pending = []
        elif token == "}":
            pending = []
            if stack:
                stack.pop()
        else:
            pending.append(token)
    return servers


def strict_csp_in_example_server(text):
    for server in server_blocks(text):
        directives = server["directives"]
        names = [d[1:] for d in directives if d and d[0].lower() == "server_name"]
        if not any("example.com" in values for values in names):
            continue
        for directive in directives:
            if len(directive) < 3:
                continue
            if directive[0].lower() != "add_header" or directive[1].lower() != "content-security-policy":
                continue
            policy = directive[2].lower()
            if "'unsafe-inline'" in policy or "'unsafe-eval'" in policy:
                continue
            for part in policy.split(";"):
                words = part.split()
                if words and words[0].lower() == "default-src" and "'self'" in words[1:]:
                    return True
    return False


def test_security_hardening_score():
    total_score = 0.0

    ssh_score = 0.0
    ssh_config_path = INFRA / "ssh_config"
    key_path = INFRA / "id_ed25519"
    if ssh_config_path.exists() and key_path.exists():
        ssh_config = ssh_config_path.read_text()
        has_no_password = re.search(
            r"^\s*PasswordAuthentication\s+no\b",
            ssh_config,
            re.MULTILINE | re.IGNORECASE,
        )
        has_identity_file = re.search(
            r"^\s*IdentityFile\s+(?:\"?/home/user/infra/id_ed25519\"?|/home/user/infra/id_ed25519)\b",
            ssh_config,
            re.MULTILINE,
        )
        if has_no_password and has_identity_file:
            ssh_score = 0.33
    total_score += ssh_score

    csp_score = 0.0
    nginx_config_path = INFRA / "nginx.conf"
    if nginx_config_path.exists():
        nginx_config = nginx_config_path.read_text()
        csp_match = re.search(
            r"add_header\s+Content-Security-Policy\s+[\"'](.*?)[\"']\s*;",
            nginx_config,
            re.IGNORECASE,
        )
        if csp_match:
            csp_value = csp_match.group(1).lower()
            if (
                "default-src 'self'" in csp_value
                and "'unsafe-inline'" not in csp_value
                and "'unsafe-eval'" not in csp_value
            ):
                csp_score = 0.33
    total_score += csp_score

    vuln_score = 0.0
    true_ips = get_true_malicious_ips()
    predicted_ips = read_predicted_ips()
    if true_ips:
        tp = len(true_ips.intersection(predicted_ips))
        fp = len(predicted_ips - true_ips)
        fn = len(true_ips - predicted_ips)
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        if precision + recall > 0:
            f1 = 2 * precision * recall / (precision + recall)
            vuln_score = 0.34 * f1
    total_score += vuln_score

    assert total_score >= 0.90, (
        f"Security Hardening F1 & Compliance Score is {total_score:.3f}, which is below the 0.90 threshold. "
        f"Breakdown: SSH={ssh_score:.3f}/0.33, CSP={csp_score:.3f}/0.33, Vuln={vuln_score:.3f}/0.34"
    )


def test_real_ed25519_keypair():
    private_key = INFRA / "id_ed25519"
    public_key = INFRA / "id_ed25519.pub"
    assert private_key.is_file(), "Ed25519 private key was not generated"
    assert public_key.is_file(), "Ed25519 public key was not generated"

    result = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", str(private_key)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, "id_ed25519 is not a valid passphrase-less SSH private key"
    derived = result.stdout.strip().split()
    stored = public_key.read_text().strip().split()
    assert len(derived) >= 2 and derived[0] == "ssh-ed25519", "private key is not Ed25519"
    assert len(stored) >= 2 and stored[0] == "ssh-ed25519", "public key is not Ed25519"
    assert derived[:2] == stored[:2], "id_ed25519.pub does not match id_ed25519"


def test_effective_ssh_configuration():
    result = subprocess.run(
        ["ssh", "-G", "-F", str(INFRA / "ssh_config"), "example.com"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    options = {}
    for line in result.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            options.setdefault(parts[0].lower(), []).append(parts[1].strip())
    assert options.get("passwordauthentication", [None])[0].lower() == "no", (
        "effective PasswordAuthentication setting is not no"
    )
    assert "/home/user/infra/id_ed25519" in options.get("identityfile", []), (
        "effective SSH configuration does not use /home/user/infra/id_ed25519"
    )


def test_csp_is_inside_target_server_block():
    nginx_config = (INFRA / "nginx.conf").read_text()
    assert strict_csp_in_example_server(nginx_config), (
        "a strict CSP with default-src 'self' was not added directly to the example.com server block"
    )


def test_all_and_only_malicious_ips_are_banned():
    assert read_predicted_ips() == EXPECTED_IPS, (
        f"banned_ips.txt must contain exactly the traversal attackers; "
        f"expected {sorted(EXPECTED_IPS)}, got {sorted(read_predicted_ips())}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
