#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import re
import pytest


def test_bashrc_env_vars():
    """Check that the required environment variables are defined in .bashrc."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"{bashrc_path} does not exist"

    with open(bashrc_path, "r") as f:
        content = f.read()

    assert re.search(r'BACKEND_1\s*=\s*["\']?127\.0\.0\.1:9001["\']?', content), "BACKEND_1 not correctly set in .bashrc"
    assert re.search(r'BACKEND_2\s*=\s*["\']?127\.0\.0\.1:9002["\']?', content), "BACKEND_2 not correctly set in .bashrc"
    assert re.search(r'FRONTEND_PORT\s*=\s*["\']?8443["\']?', content), "FRONTEND_PORT not correctly set in .bashrc"


def test_bashrc_assignments_are_active():
    """Source .bashrc in a clean shell and check the resulting shell variables."""
    script = (
        'source "$1"; rc=$?; '
        'printf "__VALUES__\\0%s\\0%s\\0%s\\0" '
        '"$BACKEND_1" "$BACKEND_2" "$FRONTEND_PORT"; exit $rc'
    )
    result = subprocess.run(
        ["env", "-i", "HOME=/home/user", "PATH=/usr/bin:/bin", "bash",
         "--noprofile", "--norc", "-c", script, "_", "/home/user/.bashrc"],
        capture_output=True,
    )
    assert result.returncode == 0, ".bashrc could not be sourced successfully"
    parts = result.stdout.split(b"\0")
    assert len(parts) >= 5 and parts[-5] == b"__VALUES__", "Could not read active variable values from .bashrc"
    assert parts[-4:] == [b"127.0.0.1:9001", b"127.0.0.1:9002", b"8443", b""], \
        "Required .bashrc variables are not active assignments with the requested values"


def test_tls_certificates():
    """Verify the self-signed certificate and key."""
    cert_path = "/home/user/certs/proxy.crt"
    key_path = "/home/user/certs/proxy.key"

    assert os.path.exists(cert_path), f"Certificate {cert_path} not found"
    assert os.path.exists(key_path), f"Private key {key_path} not found"

    # Check Common Name
    subject_cmd = ["openssl", "x509", "-in", cert_path, "-noout", "-subject"]
    subject_result = subprocess.run(subject_cmd, capture_output=True, text=True)
    assert subject_result.returncode == 0, "Failed to read certificate subject"
    assert "CN = localhost" in subject_result.stdout or "CN=localhost" in subject_result.stdout, "Certificate Common Name (CN) is not localhost"

    # Check Modulus match
    cert_mod_cmd = ["openssl", "x509", "-noout", "-modulus", "-in", cert_path]
    key_mod_cmd = ["openssl", "rsa", "-noout", "-modulus", "-in", key_path]

    cert_mod = subprocess.run(cert_mod_cmd, capture_output=True, text=True).stdout.strip()
    key_mod = subprocess.run(key_mod_cmd, capture_output=True, text=True).stdout.strip()

    assert cert_mod != "", "Failed to get certificate modulus"
    assert cert_mod == key_mod, "Certificate and private key do not match"


def test_tls_is_self_signed_rsa_2048():
    cert_path = "/home/user/certs/proxy.crt"

    subject = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"],
        capture_output=True, text=True
    )
    issuer = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"],
        capture_output=True, text=True
    )
    assert subject.returncode == 0 and issuer.returncode == 0, "Failed to inspect certificate issuer and subject"
    assert subject.stdout.strip().removeprefix("subject=") == issuer.stdout.strip().removeprefix("issuer="), \
        "Certificate issuer and subject differ; certificate is not self-signed"

    verify = subprocess.run(
        ["openssl", "verify", "-check_ss_sig", "-CAfile", cert_path, cert_path],
        capture_output=True, text=True
    )
    assert verify.returncode == 0, f"Certificate does not have a valid self-signature: {verify.stderr}"

    details = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-text"],
        capture_output=True, text=True
    )
    assert details.returncode == 0, "Failed to inspect certificate public key"
    assert re.search(r"Public-Key:\s*\(2048 bit\)", details.stdout), "Certificate RSA key is not 2048 bits"
    assert re.search(r"Public Key Algorithm:\s*(?:rsaEncryption|rsa)", details.stdout), "Certificate public key is not RSA"


def test_nginx_config_syntax():
    """Verify the NGINX configuration syntax."""
    conf_path = "/home/user/nginx-dev.conf"
    assert os.path.exists(conf_path), f"NGINX config {conf_path} not found"

    cmd = ["nginx", "-t", "-c", conf_path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"NGINX configuration syntax is invalid:\n{result.stderr}"


def test_nginx_config_contents():
    """Check that the NGINX configuration contains the required directives."""
    conf_path = "/home/user/nginx-dev.conf"
    assert os.path.exists(conf_path), f"NGINX config {conf_path} not found"

    with open(conf_path, "r") as f:
        content = f.read()

    assert "daemon off;" in content, "Directive 'daemon off;' is missing"
    assert "/home/user/nginx.pid" in content, "PID file path '/home/user/nginx.pid' is missing"
    assert "/home/user/error.log" in content, "Error log path '/home/user/error.log' is missing"
    assert "/home/user/access.log" in content, "Access log path '/home/user/access.log' is missing"
    assert "127.0.0.1:9001" in content, "Backend 1 (127.0.0.1:9001) is missing from config"
    assert "127.0.0.1:9002" in content, "Backend 2 (127.0.0.1:9002) is missing from config"
    assert re.search(r'listen\s+8443\s+ssl', content), "Server is not listening on 8443 with ssl"
    assert "proxy.crt" in content, "Certificate 'proxy.crt' is not referenced"
    assert "proxy.key" in content, "Private key 'proxy.key' is not referenced"
    assert "proxy_pass" in content and "http://microservices" in content, "proxy_pass to http://microservices is missing"


def tokenize_nginx(text):
    """Tokenize NGINX syntax while discarding comments."""
    tokens = []
    current = []
    quote = None
    escaped = False
    i = 0
    while i < len(text):
        ch = text[i]
        if escaped:
            current.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif quote is not None:
            if ch == quote:
                quote = None
            else:
                current.append(ch)
        elif ch in ("'", '"'):
            quote = ch
        elif ch == "#":
            if current:
                tokens.append("".join(current))
                current = []
            while i < len(text) and text[i] != "\n":
                i += 1
        elif ch.isspace():
            if current:
                tokens.append("".join(current))
                current = []
        elif ch in "{};":
            if current:
                tokens.append("".join(current))
                current = []
            tokens.append(ch)
        else:
            current.append(ch)
        i += 1
    assert quote is None and not escaped, "Unterminated quote or escape in NGINX configuration"
    if current:
        tokens.append("".join(current))
    return tokens


def parse_nginx(tokens):
    """Return directives as (name, arguments, child_directives_or_None)."""
    position = 0

    def parse_block(expect_close=False):
        nonlocal position
        nodes = []
        while position < len(tokens):
            if tokens[position] == "}":
                assert expect_close, "Unexpected closing brace"
                position += 1
                return nodes
            assert tokens[position] not in ("{", ";"), "Malformed NGINX directive"
            name = tokens[position]
            position += 1
            args = []
            while position < len(tokens) and tokens[position] not in (";", "{", "}"):
                args.append(tokens[position])
                position += 1
            assert position < len(tokens), f"Unterminated NGINX directive: {name}"
            terminator = tokens[position]
            if terminator == ";":
                position += 1
                nodes.append((name, args, None))
            elif terminator == "{":
                position += 1
                nodes.append((name, args, parse_block(True)))
            else:
                raise AssertionError(f"Directive {name} ended by an unexpected closing brace")
        assert not expect_close, "Unclosed NGINX block"
        return nodes

    result = parse_block(False)
    assert position == len(tokens), "Could not parse complete NGINX configuration"
    return result


def directives(nodes, name, block=None):
    return [node for node in nodes if node[0] == name and (block is None or (node[2] is not None) == block)]


def has_simple(nodes, name, predicate):
    return any(node[2] is None and predicate(node[1]) for node in nodes if node[0] == name)


def test_nginx_required_directives_are_active_and_contextual():
    """Parse active directives so comments and wrong contexts cannot satisfy requirements."""
    with open("/home/user/nginx-dev.conf", "r") as f:
        root = parse_nginx(tokenize_nginx(f.read()))

    assert has_simple(root, "daemon", lambda a: a == ["off"]), "Active top-level 'daemon off;' is missing"
    assert has_simple(root, "pid", lambda a: a == ["/home/user/nginx.pid"]), "Active top-level PID directive is incorrect"
    assert has_simple(root, "error_log", lambda a: len(a) >= 2 and a[0] == "/home/user/error.log" and a[1] == "info"), \
        "Active top-level error_log must use /home/user/error.log at info level"
    assert directives(root, "events", True), "Active top-level events block is missing"

    http_blocks = directives(root, "http", True)
    assert http_blocks, "Active top-level http block is missing"

    valid_http = False
    for _, _, http_children in http_blocks:
        access_ok = has_simple(http_children, "access_log", lambda a: len(a) >= 1 and a[0] == "/home/user/access.log")

        upstream_ok = False
        for _, args, children in directives(http_children, "upstream", True):
            if args == ["microservices"]:
                addresses = [a[0] for n, a, c in children if n == "server" and c is None and a]
                if "127.0.0.1:9001" in addresses and "127.0.0.1:9002" in addresses:
                    upstream_ok = True

        inherited_crt = has_simple(http_children, "ssl_certificate", lambda a: a == ["/home/user/certs/proxy.crt"])
        inherited_key = has_simple(http_children, "ssl_certificate_key", lambda a: a == ["/home/user/certs/proxy.key"])
        server_ok = False
        for _, _, server_children in directives(http_children, "server", True):
            listen_ok = has_simple(server_children, "listen", lambda a: "8443" in a and "ssl" in a)
            cert_ok = inherited_crt or has_simple(server_children, "ssl_certificate", lambda a: a == ["/home/user/certs/proxy.crt"])
            key_ok = inherited_key or has_simple(server_children, "ssl_certificate_key", lambda a: a == ["/home/user/certs/proxy.key"])
            proxy_ok = False
            for _, location_args, location_children in directives(server_children, "location", True):
                if location_args == ["/"] and has_simple(location_children, "proxy_pass", lambda a: a == ["http://microservices"]):
                    proxy_ok = True
            if listen_ok and cert_ok and key_ok and proxy_ok:
                server_ok = True

        if access_ok and upstream_ok and server_ok:
            valid_http = True

    assert valid_http, "No http block has the required active access log, upstream, and SSL proxy server configuration"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
