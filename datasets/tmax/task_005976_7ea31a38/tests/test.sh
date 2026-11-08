#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import hashlib
import json
import os
import secrets
import stat
import subprocess

import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/auth_logs.txt"
GO_SOURCE = f"{HOME}/secops.go"
CLEAN = f"{HOME}/clean_auth_logs.txt"
POLICY = f"{HOME}/deny_policy.yaml"
CHECKSUM = f"{HOME}/checksum.txt"

CANONICAL_LOGS = b'''[2023-10-01T10:00:01Z] | 192.168.1.100 | 200 | eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
[2023-10-01T10:05:12Z] | 203.0.113.45 | 401 | eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbiJ9.
[2023-10-01T10:12:33Z] | 198.51.100.22 | 200 | eyJhbGciOiJub25lIn0=.eyJyb2xlIjoiYWRtaW4iLCJ1c2VyIjoiYm9iIn0=.
[2023-10-01T10:15:44Z] | 10.0.0.5 | 200 | eyJhbGciOiJIUzI1NiJ9.eyJuYW1lIjoiYWxpY2UifQ.abcdef123456
[2023-10-01T10:20:01Z] | 203.0.113.99 | 200 | eyJhbGciOiAibm9uZSJ9.eyJzdWIiOiJzeXNhZG1pbiJ9.
'''


def expected_clean(data):
    output = []
    for line in data.splitlines(keepends=True):
        ending = b""
        body = line
        if body.endswith(b"\r\n"):
            body, ending = body[:-2], b"\r\n"
        elif body.endswith(b"\n"):
            body, ending = body[:-1], b"\n"
        parts = body.split(b" | ", 3)
        assert len(parts) == 4, "Test input is not in the documented log format"
        output.append(b" | ".join(parts[:3] + [b"[REDACTED_JWT]"]) + ending)
    return b"".join(output)


def malicious_ips(data):
    found = set()
    for raw_line in data.decode("utf-8").splitlines():
        parts = raw_line.split(" | ", 3)
        assert len(parts) == 4
        ip, status, token = parts[1], parts[2], parts[3]
        header = token.split(".", 1)[0]
        try:
            padded = header + "=" * ((-len(header)) % 4)
            decoded = base64.urlsafe_b64decode(padded.encode("ascii"))
            value = json.loads(decoded.decode("utf-8"))
        except Exception:
            continue
        if status == "200" and isinstance(value, dict) and value.get("alg") == "none":
            found.add(ip + "/32")
    return sorted(found)


def b64url_json(value, padded=False):
    encoded = base64.urlsafe_b64encode(json.dumps(value, separators=(",", ":")).encode()).decode()
    return encoded if padded else encoded.rstrip("=")


def run_program(binary):
    result = subprocess.run(
        [binary], cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"secops.go exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_go_program_compiles_runs_and_redacts_dynamic_input():
    assert os.path.exists(GO_SOURCE), f"{GO_SOURCE} does not exist."
    assert os.path.isfile(GO_SOURCE), f"{GO_SOURCE} is not a file."
    assert stat.S_ISREG(os.lstat(GO_SOURCE).st_mode), f"{GO_SOURCE} must be a regular file."
    assert os.path.getsize(GO_SOURCE) > 0, f"{GO_SOURCE} is empty."

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/secops-under-test", GO_SOURCE],
        cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60
    )
    assert build.returncode == 0, f"secops.go did not compile:\n{build.stderr}"

    with open(SOURCE, "rb") as f:
        assert f.read() == CANONICAL_LOGS, "The supplied auth_logs.txt was modified."

    suffix = secrets.randbelow(200) + 20
    dynamic = (
        f"[2026-01-02T03:04:05Z] | 172.19.7.{suffix} | 200 | "
        f"{b64url_json({'typ': 'JWT', 'alg': 'none'})}.e30.\n"
        f"[2026-01-02T03:04:06Z] | 172.19.8.{suffix} | 401 | "
        f"{b64url_json({'alg': 'none'}, padded=True)}.e30.\n"
        f"[2026-01-02T03:04:07Z] | 172.19.9.{suffix} | 200 | "
        f"{b64url_json({'alg': 'HS256'})}.e30.signature\n"
    ).encode()

    try:
        with open(SOURCE, "wb") as f:
            f.write(dynamic)
        if os.path.lexists(CLEAN):
            os.remove(CLEAN)
        run_program("/tmp/secops-under-test")
        assert os.path.isfile(CLEAN), "The Go program did not create clean_auth_logs.txt."
        with open(CLEAN, "rb") as f:
            assert f.read() == expected_clean(dynamic), "The Go program redacted a dynamic input incorrectly."
    finally:
        with open(SOURCE, "wb") as f:
            f.write(CANONICAL_LOGS)

    if os.path.lexists(CLEAN):
        os.remove(CLEAN)
    run_program("/tmp/secops-under-test")
    assert os.path.isfile(CLEAN), "The Go program did not recreate clean_auth_logs.txt for the supplied logs."
    with open(CLEAN, "rb") as f:
        assert f.read() == expected_clean(CANONICAL_LOGS), "Cleaned logs are not the exact expected output."


def test_clean_auth_logs_redacted():
    assert os.path.exists(CLEAN), f"{CLEAN} does not exist."

    with open(SOURCE, "r") as f:
        original_lines = f.read().splitlines()
    with open(CLEAN, "r") as f:
        clean_lines = f.read().splitlines()

    assert len(original_lines) == len(clean_lines), "Cleaned logs line count does not match original logs."
    for orig, clean in zip(original_lines, clean_lines):
        parts_orig = orig.split(" | ")
        parts_clean = clean.split(" | ")
        assert len(parts_clean) == 4, f"Cleaned log line does not have 4 parts: {clean}"
        assert parts_clean[0] == parts_orig[0], "Timestamp was modified."
        assert parts_clean[1] == parts_orig[1], "IP address was modified."
        assert parts_clean[2] == parts_orig[2], "HTTP status was modified."
        assert parts_clean[3] == "[REDACTED_JWT]", f"JWT was not correctly redacted in line: {clean}"

    with open(CLEAN, "rb") as f:
        assert f.read() == expected_clean(CANONICAL_LOGS)


def parse_scalar(text):
    text = text.strip()
    if text == "":
        return None
    if text[0:1] in ("'", '"'):
        try:
            value = ast.literal_eval(text)
        except Exception as exc:
            raise AssertionError(f"Invalid quoted YAML scalar {text!r}: {exc}")
        assert isinstance(value, str)
        return value
    if text in ("[]", "{}"):
        return [] if text == "[]" else {}
    if text.startswith("[") or text.startswith("{"):
        try:
            return json.loads(text)
        except Exception as exc:
            raise AssertionError(f"Invalid inline YAML value {text!r}: {exc}")
    if text in ("null", "Null", "NULL", "~"):
        return None
    return text


def parse_yaml_subset(content):
    lines = []
    for number, raw in enumerate(content.splitlines(), 1):
        assert "\t" not in raw, f"Tabs are not permitted for YAML indentation (line {number})."
        if not raw.strip() or raw.lstrip().startswith("#") or raw.strip() == "---":
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        lines.append((indent, raw.strip(), number))
    assert lines, "Policy YAML is empty."

    def mapping_pair(text, number):
        assert ":" in text, f"Expected a YAML mapping on line {number}."
        key, value = text.split(":", 1)
        key = key.strip().strip("'\"")
        assert key, f"Empty YAML key on line {number}."
        return key, value.strip()

    def block(pos, indent):
        assert pos < len(lines) and lines[pos][0] == indent
        is_list = lines[pos][1] == "-" or lines[pos][1].startswith("- ")
        result = [] if is_list else {}
        while pos < len(lines) and lines[pos][0] == indent:
            text, number = lines[pos][1], lines[pos][2]
            if is_list:
                assert text == "-" or text.startswith("- "), f"Mixed YAML collection on line {number}."
                rest = text[1:].strip()
                pos += 1
                if not rest:
                    assert pos < len(lines) and lines[pos][0] > indent, f"Empty list item on line {number}."
                    value, pos = block(pos, lines[pos][0])
                    result.append(value)
                    continue
                if ":" not in rest:
                    result.append(parse_scalar(rest))
                    continue
                key, raw_value = mapping_pair(rest, number)
                item = {}
                if raw_value:
                    item[key] = parse_scalar(raw_value)
                else:
                    assert pos < len(lines) and lines[pos][0] > indent, f"Missing value for {key!r}."
                    item[key], pos = block(pos, lines[pos][0])
                if pos < len(lines) and lines[pos][0] > indent:
                    extra_indent = lines[pos][0]
                    extra, pos = block(pos, extra_indent)
                    assert isinstance(extra, dict), f"Invalid continuation of list mapping after line {number}."
                    assert not set(item).intersection(extra), "Duplicate YAML key."
                    item.update(extra)
                result.append(item)
            else:
                assert not (text == "-" or text.startswith("- ")), f"Mixed YAML collection on line {number}."
                key, raw_value = mapping_pair(text, number)
                assert key not in result, f"Duplicate YAML key {key!r}."
                pos += 1
                if raw_value:
                    result[key] = parse_scalar(raw_value)
                else:
                    assert pos < len(lines) and lines[pos][0] > indent, f"Missing value for {key!r}."
                    result[key], pos = block(pos, lines[pos][0])
        return result, pos

    document, end = block(0, lines[0][0])
    assert end == len(lines), f"Invalid YAML indentation near line {lines[end][2]}."
    assert isinstance(document, dict), "The YAML document must be a mapping."
    return document


def test_deny_policy_yaml():
    assert os.path.exists(POLICY), f"{POLICY} does not exist."
    with open(POLICY, "r") as f:
        content = f.read()

    # Preserve the original required element assertions.
    assert "kind: NetworkPolicy" in content, "Missing 'kind: NetworkPolicy' in yaml."
    assert "app: auth-service" in content, "Missing 'app: auth-service' label selector."
    assert "cidr: 0.0.0.0/0" in content, "Missing 'cidr: 0.0.0.0/0' in yaml."
    assert "except:" in content, "Missing 'except:' array in yaml."

    doc = parse_yaml_subset(content)
    assert doc.get("kind") == "NetworkPolicy", "YAML kind must be NetworkPolicy."
    spec = doc.get("spec")
    assert isinstance(spec, dict), "NetworkPolicy must contain a spec mapping."
    selector = spec.get("podSelector")
    assert isinstance(selector, dict), "spec.podSelector must be a mapping."
    assert selector.get("matchLabels") == {"app": "auth-service"}, "Policy must select app: auth-service pods."

    ingress = spec.get("ingress")
    assert isinstance(ingress, list) and len(ingress) == 1, "Policy must contain exactly one ingress rule."
    rule = ingress[0]
    assert isinstance(rule, dict) and set(rule) == {"from"}, "Ingress rule must only define its source peers."
    peers = rule.get("from")
    assert isinstance(peers, list) and len(peers) == 1, "Ingress must contain exactly one ipBlock peer."
    peer = peers[0]
    assert isinstance(peer, dict) and set(peer) == {"ipBlock"}, "Ingress peer must be an ipBlock."
    ip_block = peer["ipBlock"]
    assert isinstance(ip_block, dict), "ipBlock must be a mapping."
    assert ip_block.get("cidr") == "0.0.0.0/0", "ipBlock cidr must be 0.0.0.0/0."

    except_lines = ip_block.get("except")
    assert isinstance(except_lines, list), "ipBlock.except must be an array."
    assert all(isinstance(ip, str) for ip in except_lines), "Every except entry must be a string."

    expected_ips = malicious_ips(CANONICAL_LOGS)
    assert expected_ips == ["198.51.100.22/32", "203.0.113.99/32"]
    for ip in expected_ips:
        assert ip in except_lines, f"Malicious IP {ip} not found in the except block of {POLICY}."
    found_ips = [ip for ip in except_lines if ip in expected_ips]
    assert found_ips == sorted(found_ips), "The IPs in the except array are not sorted in ascending alphabetical order."
    assert except_lines == expected_ips, "The except array must contain only the identified malicious IPs, sorted alphabetically."


def test_checksum():
    assert os.path.exists(CHECKSUM), f"{CHECKSUM} does not exist."
    with open(CLEAN, "rb") as f:
        clean_data = f.read()
    actual_hash = hashlib.sha256(clean_data).hexdigest()
    with open(CHECKSUM, "r") as f:
        checksum_content = f.read().strip()

    assert actual_hash in checksum_content, f"The correct SHA256 hash ({actual_hash}) was not found in {CHECKSUM}."
    assert CLEAN in checksum_content, f"The file path {CLEAN} was not found in {CHECKSUM}."
    expected_hash = hashlib.sha256(expected_clean(CANONICAL_LOGS)).hexdigest()
    assert checksum_content == f"{expected_hash}  {CLEAN}", "checksum.txt is not in exact standard sha256sum format."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
