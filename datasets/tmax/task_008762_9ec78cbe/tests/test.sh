#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import secrets
import string
import subprocess
from collections import Counter
from pathlib import Path


def test_cpp_source_exists():
    path = "/home/user/policy_scanner.cpp"
    assert os.path.isfile(path), f"Missing source file: {path}"


def test_cpp_binary_exists_and_executable():
    path = "/home/user/policy_scanner"
    assert os.path.isfile(path), f"Missing compiled binary: {path}"
    assert os.access(path, os.X_OK), f"Binary is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "policy_scanner is not a compiled ELF executable"


def test_scan_report_exists_and_correct():
    path = "/home/user/scan_report.log"
    assert os.path.isfile(path), f"Missing report file: {path}"

    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "VULNERABILITY: JWT with alg=none found in app.conf",
        "VULNERABILITY: Weak password secret found in app.conf",
        "VULNERABILITY: Deprecated SSH key (ssh-dss) found in keys.txt"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected vulnerability not found in {path}: {expected}"

    assert len(lines) == len(expected_lines), f"Expected exactly {len(expected_lines)} vulnerabilities, found {len(lines)}"

    app_conf_indices = [i for i, line in enumerate(lines) if "app.conf" in line]
    keys_txt_indices = [i for i, line in enumerate(lines) if "keys.txt" in line]

    assert len(app_conf_indices) == 2, "Expected exactly 2 vulnerabilities for app.conf"
    assert len(keys_txt_indices) == 1, "Expected exactly 1 vulnerability for keys.txt"
    assert max(app_conf_indices) < min(keys_txt_indices), "Vulnerabilities must be grouped and sorted alphabetically by filename"


def _b64url(value):
    return base64.urlsafe_b64encode(value.encode()).decode().rstrip("=")


def _hash(word):
    return sum(ord(c) for c in word) % 256


def _random_words():
    while True:
        first = "pw" + "".join(random.choice(string.ascii_lowercase) for _ in range(14))
        second = "pw" + "".join(random.choice(string.ascii_lowercase) for _ in range(14))
        if first != second and _hash(first) != _hash(second):
            return first, second


def test_scanner_behavior_on_generated_inputs():
    token = secrets.token_hex(8)
    scan_dir = Path("/tmp") / ("policy_scan_case_" + token)
    scan_dir.mkdir()

    rebuilt = Path("/tmp") / ("policy_scanner_rebuilt_" + token)
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "/home/user/policy_scanner.cpp", "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"policy_scanner.cpp does not compile: {compile_result.stderr}"

    report = Path("/home/user/scan_report.log")
    wordlist = Path("/home/user/wordlist.txt")
    old_report = report.read_bytes() if report.exists() else None
    old_wordlist = wordlist.read_bytes() if wordlist.exists() else None

    password1, password2 = _random_words()
    wordlist.write_text(password1 + "\n" + password2 + "\n", encoding="utf-8")

    alpha = "a_" + token + ".cfg"
    middle = "m_" + token + ".txt"
    zeta = "z_" + token + ".data"

    none_header1 = json.dumps(
        {"nonce": secrets.token_hex(12), "alg": "none", "typ": "JWT"},
        separators=(",", ":"),
    )
    none_header2 = json.dumps(
        {"typ": "JWT", "marker": secrets.token_hex(10), "alg": "none"},
        separators=(",", ":"),
    )
    safe_header = json.dumps(
        {"note": "none", "nonce": secrets.token_hex(12), "alg": "HS256"},
        separators=(",", ":"),
    )

    jwt_none1 = _b64url(none_header1) + "." + _b64url("{}") + "."
    jwt_none2 = _b64url(none_header2) + "." + _b64url("{}") + "."
    jwt_safe = _b64url(safe_header) + "." + _b64url("{}") + ".signature"

    (scan_dir / alpha).write_text(
        "jwt=" + jwt_none1 + "\n"
        + "custom_hash=" + str(_hash(password1)) + "\n"
        + "ssh-dss AAAAB3NzaGenerated\n"
        + "xjwt=" + jwt_none2 + "\n",
        encoding="utf-8",
    )
    (scan_dir / middle).write_text(
        "jwt=" + jwt_safe + "\n"
        + " ssh-dss not-at-line-start\n"
        + "prefix custom_hash=" + str(_hash(password2)) + "\n"
        + "custom_hash=999\n",
        encoding="utf-8",
    )
    (scan_dir / zeta).write_text(
        "custom_hash=" + str(_hash(password2)) + "\n"
        + "jwt=" + jwt_none2 + "\n",
        encoding="utf-8",
    )

    expected = [
        f"VULNERABILITY: JWT with alg=none found in {alpha}",
        f"VULNERABILITY: Weak password {password1} found in {alpha}",
        f"VULNERABILITY: Deprecated SSH key (ssh-dss) found in {alpha}",
        f"VULNERABILITY: Weak password {password2} found in {zeta}",
        f"VULNERABILITY: JWT with alg=none found in {zeta}",
    ]

    try:
        for executable in [Path("/home/user/policy_scanner"), rebuilt]:
            if report.exists():
                report.unlink()

            result = subprocess.run(
                [str(executable), str(scan_dir)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, f"Scanner failed on generated input: {result.stderr}"
            assert report.is_file(), "Scanner did not create /home/user/scan_report.log"

            lines = [line.strip() for line in report.read_text(encoding="utf-8").splitlines() if line.strip()]
            assert Counter(lines) == Counter(expected), f"Incorrect generated-input report: {lines}"

            reported_filenames = [line.rsplit(" found in ", 1)[1] for line in lines]
            assert reported_filenames == sorted(reported_filenames), "Report is not sorted and grouped by filename"
    finally:
        if old_report is None:
            if report.exists():
                report.unlink()
        else:
            report.write_bytes(old_report)

        if old_wordlist is None:
            if wordlist.exists():
                wordlist.unlink()
        else:
            wordlist.write_bytes(old_wordlist)

        if rebuilt.exists():
            rebuilt.unlink()
        for child in scan_dir.iterdir():
            child.unlink()
        scan_dir.rmdir()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
