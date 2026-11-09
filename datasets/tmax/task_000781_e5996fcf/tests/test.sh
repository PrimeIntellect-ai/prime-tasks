#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile

SCRIPT = "/home/user/policy_scanner.py"
REPORT = "/home/user/scan_report.json"
ORIGINAL_CERT = "/home/user/cert.pem"
ORIGINAL_HEADERS = "/home/user/headers.json"
VALID_RULES = {"TLS_EXPIRED", "TLS_WEAK_SIG", "CSP_MISSING", "CSP_UNSAFE"}


def expected_violations(cert_path, headers_path):
    expected = []

    expired = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-checkend", "0"],
        capture_output=True,
        timeout=15,
    )
    if expired.returncode != 0:
        expected.append("TLS_EXPIRED")

    sig = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-text"],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    if "sha1WithRSAEncryption" in sig.stdout or "md5WithRSAEncryption" in sig.stdout:
        expected.append("TLS_WEAK_SIG")

    with open(headers_path, "r") as f:
        headers = json.load(f)

    csp_header = None
    for key, value in headers.items():
        if key.lower() == "content-security-policy":
            csp_header = value
            break

    if csp_header is None:
        expected.append("CSP_MISSING")
    elif "'unsafe-inline'" in csp_header.lower() or "'unsafe-eval'" in csp_header.lower():
        expected.append("CSP_UNSAFE")

    return sorted(expected)


def run_scanner(cert_path, headers_path):
    if os.path.exists(REPORT):
        os.unlink(REPORT)

    result = subprocess.run(
        ["python3", SCRIPT, cert_path, headers_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Scanner exited with {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(REPORT), "The scanner did not create /home/user/scan_report.json."

    with open(REPORT, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError("The scanner report is not valid JSON.") from exc

    assert isinstance(report, dict), "The root of the JSON report must be a dictionary."
    assert set(report.keys()) == {"violations"}, "The report must contain only the 'violations' key."
    assert isinstance(report["violations"], list), "The 'violations' key must be a list."
    assert all(isinstance(v, str) for v in report["violations"]), "Every violation must be a string."
    assert all(v in VALID_RULES for v in report["violations"]), "The report contains an unknown rule ID."
    assert report["violations"] == sorted(report["violations"]), "Violations must be sorted alphabetically."
    assert len(report["violations"]) == len(set(report["violations"])), "Violations must not be duplicated."
    return report


def make_certificate(path, key_path, weak=False, expired=False):
    openssl_cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", path, "-days", "2", "-nodes",
        "-subj", f"/CN=scanner-test-{secrets.token_hex(8)}",
        "-sha1" if weak else "-sha256",
    ]
    if expired:
        openssl_cmd = ["faketime", "2010-01-01 00:00:00"] + openssl_cmd
    subprocess.run(openssl_cmd, capture_output=True, text=True, timeout=30, check=True)


def test_policy_scanner_script_exists():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."


def test_scan_report_exists_and_valid_json():
    run_scanner(ORIGINAL_CERT, ORIGINAL_HEADERS)
    assert os.path.isfile(REPORT), f"The report file {REPORT} was not created."

    with open(REPORT, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {REPORT} does not contain valid JSON."

    assert isinstance(report, dict), "The root of the JSON report must be a dictionary."
    assert "violations" in report, "The JSON report is missing the 'violations' key."
    assert isinstance(report["violations"], list), "The 'violations' key must be a list."


def test_scan_report_correct_violations():
    report = run_scanner(ORIGINAL_CERT, ORIGINAL_HEADERS)
    expected = expected_violations(ORIGINAL_CERT, ORIGINAL_HEADERS)
    actual = sorted(report.get("violations", []))
    assert actual == expected, (
        f"Expected violations {expected}, but got {actual}. "
        "Ensure your script correctly identifies all violations according to the rules."
    )


def test_requires_exactly_two_arguments():
    no_args = subprocess.run(
        ["python3", SCRIPT], capture_output=True, text=True, timeout=10
    )
    assert no_args.returncode != 0, "The scanner must reject invocation with no arguments."

    extra_arg = subprocess.run(
        ["python3", SCRIPT, ORIGINAL_CERT, ORIGINAL_HEADERS, "unexpected"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert extra_arg.returncode != 0, "The scanner must reject invocation with more than two arguments."


def test_scanner_on_alternate_inputs():
    try:
        with tempfile.TemporaryDirectory(prefix="policy-scanner-") as td:
            valid_cert = os.path.join(td, secrets.token_hex(8) + ".pem")
            valid_key = os.path.join(td, secrets.token_hex(8) + ".key")
            expired_weak_cert = os.path.join(td, secrets.token_hex(8) + ".pem")
            expired_weak_key = os.path.join(td, secrets.token_hex(8) + ".key")
            make_certificate(valid_cert, valid_key, weak=False, expired=False)
            make_certificate(expired_weak_cert, expired_weak_key, weak=True, expired=True)

            safe_headers = os.path.join(td, secrets.token_hex(8) + ".json")
            missing_headers = os.path.join(td, secrets.token_hex(8) + ".json")
            unsafe_headers = os.path.join(td, secrets.token_hex(8) + ".json")

            with open(safe_headers, "w") as f:
                json.dump({
                    "Content-Security-Policy": "default-src 'self'; object-src 'none'",
                    "X-Test-Nonce": secrets.token_hex(12),
                }, f)
            with open(missing_headers, "w") as f:
                json.dump({"X-Test-Nonce": secrets.token_hex(12)}, f)
            with open(unsafe_headers, "w") as f:
                json.dump({
                    "Content-Security-Policy": "default-src 'self'; script-src 'self' 'UnSaFe-EvAl'",
                    "X-Test-Nonce": secrets.token_hex(12),
                }, f)

            cases = [
                (valid_cert, safe_headers),
                (valid_cert, missing_headers),
                (valid_cert, unsafe_headers),
                (expired_weak_cert, safe_headers),
                (expired_weak_cert, missing_headers),
            ]
            for cert_path, headers_path in cases:
                expected = expected_violations(cert_path, headers_path)
                report = run_scanner(cert_path, headers_path)
                assert report["violations"] == expected, (
                    f"For alternate inputs {cert_path!r} and {headers_path!r}, "
                    f"expected {expected} but got {report['violations']}."
                )
    finally:
        # Leave the required final report corresponding to the provided artifacts.
        if os.path.isfile(SCRIPT):
            run_scanner(ORIGINAL_CERT, ORIGINAL_HEADERS)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
