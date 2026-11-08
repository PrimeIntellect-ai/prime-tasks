#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile


def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=10, **kwargs)


def test_report_txt_content():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"{report_path} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {report_path}, found {len(lines)}."
    assert lines[0] == "target_uri", f"Line 1 of report.txt is incorrect. Expected 'target_uri', got '{lines[0]}'."
    assert lines[1] == "8492", f"Line 2 of report.txt is incorrect. Expected '8492', got '{lines[1]}'."
    assert lines[2] == "DarkOverlord_Node", f"Line 3 of report.txt is incorrect. Expected 'DarkOverlord_Node', got '{lines[2]}'."

    with open(report_path, "r") as f:
        raw_lines = f.read().splitlines()
    assert raw_lines == ["target_uri", "8492", "DarkOverlord_Node"], \
        "report.txt must contain exactly the three required lines without extra blank lines."


def test_server_patched_exists_and_executable():
    binary_path = "/home/user/server_patched"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing."
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable."

    result = run([binary_path])
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    locations = re.findall(rb"(?im)^Location:\s*([^\r\n]+)", result.stdout)
    assert locations == [b"/home"], \
        f"The compiled server did not reject its built-in malicious redirect: {result.stdout!r}"


def test_server_c_patched_logic():
    src_path = "/home/user/server.c"
    assert os.path.isfile(src_path), f"{src_path} is missing."

    with open(src_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    has_slash_check = "('/'" in content or '"/"' in content or "strncmp" in content or content.find("[0] == '/'") != -1 or "strchr" in content
    has_http_check = "http" in content
    has_home_default = "/home" in content
    assert has_slash_check or has_http_check or has_home_default, \
        "The C source code does not appear to contain the required open redirect mitigation logic (checking for '/', 'http', or defaulting to '/home')."


def test_server_redirect_behavior():
    # Include the submitted source in a harness so handle_login can be exercised
    # against verifier-selected requests rather than only its hard-coded main().
    harness = r'''
#define main submitted_server_main
#include "/home/user/server.c"
#undef main
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    handle_login(argv[1]);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        harness_c = os.path.join(td, "harness.c")
        harness_bin = os.path.join(td, "harness")
        with open(harness_c, "w") as f:
            f.write(harness)
        compiled = run(["gcc", harness_c, "-o", harness_bin])
        assert compiled.returncode == 0, \
            f"Patched server source does not compile with gcc: {compiled.stderr.decode(errors='replace')}"

        cases = [
            ("GET /login?target_uri=/account HTTP/1.1", "/account"),
            ("GET /login?target_uri=/nested/path HTTP/1.1", "/nested/path"),
            ("GET /login?target_uri=http://evil.example/x HTTP/1.1", "/home"),
            ("GET /login?target_uri=https://evil.example/x HTTP/1.1", "/home"),
            ("GET /login?target_uri=//evil.example/x HTTP/1.1", "/home"),
            ("GET /login?target_uri=relative/path HTTP/1.1", "/home"),
            ("GET /login?target_uri=/jump?u=http://evil.example HTTP/1.1", "/home"),
            ("GET /login?target_uri=/jump?u=https://evil.example HTTP/1.1", "/home"),
        ]
        for request, expected in cases:
            result = run([harness_bin, request])
            assert result.returncode == 0, \
                f"Server failed for request {request!r}: {result.stderr.decode(errors='replace')}"
            locations = re.findall(rb"(?im)^Location:\s*([^\r\n]+)", result.stdout)
            decoded = [x.decode(errors="replace").strip() for x in locations]
            assert decoded == [expected], \
                f"For request {request!r}, expected Location: {expected}, got output {result.stdout!r}"


def test_evidence_files_exist_and_permissions():
    evidence_dir = "/home/user/evidence"
    assert os.path.isdir(evidence_dir), f"Directory {evidence_dir} is missing. Did you extract the zip?"

    expected_files = ["root.pem", "intermediate.pem", "rogue.pem"]
    for file_name in expected_files:
        file_path = os.path.join(evidence_dir, file_name)
        assert os.path.isfile(file_path), f"Extracted file {file_path} is missing."

        st = os.stat(file_path)
        perms = stat.S_IMODE(st.st_mode)
        assert perms == 0o400, f"Permissions for {file_path} are incorrect. Expected 400 (read-only for owner), got {oct(perms)}."

    # The permission requirement applies to every recovered file, not only names
    # that happen to match the expected certificate names.
    for root, _, files in os.walk(evidence_dir):
        for name in files:
            path = os.path.join(root, name)
            perms = stat.S_IMODE(os.stat(path).st_mode)
            assert perms == 0o400, \
                f"Permissions for {path} are incorrect. Expected 400, got {oct(perms)}."


def test_evidence_is_recovered_and_certificate_chain_is_valid():
    evidence_dir = "/home/user/evidence"
    archive = "/home/user/evidence.zip"
    password = "target_uri8492"

    # Confirm these are the actual files recovered from the encrypted archive.
    for name in ["root.pem", "intermediate.pem", "rogue.pem"]:
        archived = run(["unzip", "-p", "-P", password, archive, f"evidence/{name}"])
        assert archived.returncode == 0 and archived.stdout, \
            f"Could not read evidence/{name} from the encrypted evidence archive."
        with open(os.path.join(evidence_dir, name), "rb") as f:
            recovered = f.read()
        assert recovered == archived.stdout, \
            f"{name} is not the certificate recovered from evidence.zip."

    root = os.path.join(evidence_dir, "root.pem")
    intermediate = os.path.join(evidence_dir, "intermediate.pem")
    rogue = os.path.join(evidence_dir, "rogue.pem")

    for cert in [root, intermediate, rogue]:
        parsed = run(["openssl", "x509", "-in", cert, "-noout"])
        assert parsed.returncode == 0, \
            f"{cert} is not a valid X.509 certificate: {parsed.stderr.decode(errors='replace')}"

    root_check = run(["openssl", "verify", "-CAfile", root, root])
    assert root_check.returncode == 0, root_check.stderr.decode(errors="replace")
    int_check = run(["openssl", "verify", "-CAfile", root, intermediate])
    assert int_check.returncode == 0, int_check.stderr.decode(errors="replace")
    chain_check = run(["openssl", "verify", "-CAfile", root, "-untrusted", intermediate, rogue])
    assert chain_check.returncode == 0, \
        f"The root -> intermediate -> rogue chain is invalid: {chain_check.stderr.decode(errors='replace')}"

    subject = run(["openssl", "x509", "-in", rogue, "-noout", "-subject", "-nameopt", "RFC2253"])
    assert subject.returncode == 0, subject.stderr.decode(errors="replace")
    assert subject.stdout.decode().strip() == "subject=CN=DarkOverlord_Node", \
        f"Unexpected rogue certificate subject: {subject.stdout.decode(errors='replace').strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
