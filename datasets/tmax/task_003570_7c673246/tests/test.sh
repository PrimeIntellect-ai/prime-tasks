#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

BACKUP_DIR="$(mktemp -d)"
cp -a /home/user/legacy_auth_bin "$BACKUP_DIR/legacy_auth_bin"
cp -a /home/user/certs "$BACKUP_DIR/certs"
cp -a /home/user/tokens "$BACKUP_DIR/tokens"
if [ -e /home/user/audit_report.json ]; then
    cp -a /home/user/audit_report.json "$BACKUP_DIR/audit_report.json"
fi

restore_state() {
    rm -f /home/user/legacy_auth_bin /home/user/audit_report.json
    rm -rf /home/user/certs /home/user/tokens
    cp -a "$BACKUP_DIR/legacy_auth_bin" /home/user/legacy_auth_bin
    cp -a "$BACKUP_DIR/certs" /home/user/certs
    cp -a "$BACKUP_DIR/tokens" /home/user/tokens
    if [ -e "$BACKUP_DIR/audit_report.json" ]; then
        cp -a "$BACKUP_DIR/audit_report.json" /home/user/audit_report.json
    fi
    rm -rf "$BACKUP_DIR"
}
trap restore_state EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import pathlib
import subprocess
import uuid

SCRIPT = "/home/user/enforce_policy.py"
REPORT = "/home/user/audit_report.json"
BINARY = "/home/user/legacy_auth_bin"
CERTS = pathlib.Path("/home/user/certs")
TOKENS = pathlib.Path("/home/user/tokens")


def run_submission():
    if os.path.exists(REPORT):
        os.unlink(REPORT)
    result = subprocess.run(
        ["python3", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"enforce_policy.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), f"Expected audit report not found at {REPORT}"
    with open(REPORT, "r", encoding="utf-8") as f:
        return json.load(f)


def assert_report(report, issuer, chain_valid, vulnerable):
    assert "issuer_id" in report, "Missing 'issuer_id' in audit report"
    assert report["issuer_id"] == issuer, (
        f"Incorrect issuer_id: expected {issuer!r}, got {report['issuer_id']!r}"
    )
    assert "chain_valid" in report, "Missing 'chain_valid' in audit report"
    assert report["chain_valid"] is chain_valid, (
        f"Incorrect chain_valid: expected {chain_valid}, got {report['chain_valid']}"
    )
    assert "vulnerable_tokens" in report, "Missing 'vulnerable_tokens' in audit report"
    actual_tokens = report["vulnerable_tokens"]
    assert isinstance(actual_tokens, list), (
        f"'vulnerable_tokens' should be a list, got {type(actual_tokens)}"
    )
    assert sorted(actual_tokens) == vulnerable, (
        f"Incorrect vulnerable_tokens: expected {vulnerable}, got {actual_tokens}"
    )


def jwt_with_header(header):
    encoded = base64.urlsafe_b64encode(
        json.dumps(header, separators=(",", ":")).encode("utf-8")
    ).decode("ascii").rstrip("=")
    payload = base64.urlsafe_b64encode(b'{"sub":"audit"}').decode("ascii").rstrip("=")
    return f"{encoded}.{payload}.signature"


def test_script_executes_and_audits_inputs():
    assert os.path.isfile(SCRIPT), f"Expected audit script not found at {SCRIPT}"

    # Preserve the original verifier's assertions, but derive the report by
    # actually executing the submitted artifact rather than trusting a stale file.
    report = run_submission()
    assert_report(
        report,
        "SEC_8832_XYZ",
        True,
        ["token2.jwt", "token3.jwt"],
    )

    # Replace the ELF and JWT corpus with values selected by the verifier. This
    # ensures issuer extraction and JWT header decoding are really performed.
    issuer = "VERIFY_" + uuid.uuid4().hex.upper()
    source = pathlib.Path("/tmp/verifier_legacy_auth.c")
    source.write_text(
        '#include <stdio.h>\n'
        f'const char issuer_blob[] = "ISSUER_ID={issuer}";\n'
        'int main(void) { puts(issuer_blob); return 0; }\n',
        encoding="utf-8",
    )
    subprocess.run(["gcc", str(source), "-o", BINARY], check=True, timeout=30)

    for item in TOKENS.iterdir():
        if item.is_file() or item.is_symlink():
            item.unlink()
    (TOKENS / "ordinary.jwt").write_text(
        jwt_with_header({"alg": "HS256", "typ": "JWT"}), encoding="utf-8"
    )
    (TOKENS / "alpha-bypass.jwt").write_text(
        jwt_with_header({"alg": "NoNe", "typ": "JWT"}), encoding="utf-8"
    )
    (TOKENS / "zeta-bypass.jwt").write_text(
        jwt_with_header({"typ": "JWT", "alg": "NONE"}), encoding="utf-8"
    )

    report = run_submission()
    assert_report(
        report,
        issuer,
        True,
        ["alpha-bypass.jwt", "zeta-bypass.jwt"],
    )

    # Install a parseable, currently valid, but untrusted self-signed leaf. It
    # cannot chain through the supplied intermediate to the supplied root.
    rogue_key = "/tmp/verifier_rogue_leaf.key"
    subprocess.run(
        [
            "openssl", "req", "-new", "-x509", "-nodes", "-days", "2",
            "-keyout", rogue_key,
            "-out", str(CERTS / "leaf.pem"),
            "-subj", "/C=US/O=Verifier/CN=UntrustedLeaf",
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
    )

    report = run_submission()
    assert_report(
        report,
        issuer,
        False,
        ["alpha-bypass.jwt", "zeta-bypass.jwt"],
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
