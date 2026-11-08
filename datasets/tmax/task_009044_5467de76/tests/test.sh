#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import secrets
import shutil
import subprocess
import tempfile

PARSER_SOURCE = "/home/user/audit_parser.c"
PARSER = "/home/user/audit_parser"
SCRIPT = "/home/user/generate_audit.sh"
AUDIT_DATA = "/home/user/audit_data"
FINAL_CSV = "/home/user/final_audit.csv"


def test_final_audit_csv_exists():
    assert os.path.isfile("/home/user/final_audit.csv"), "The file /home/user/final_audit.csv does not exist."


def test_final_audit_csv_content():
    expected_rows = [
        ["Request", "SessionID", "Filename", "TraversalAttempt", "CertValid", "HashMatch"],
        ["req1.txt", "abc123xyz", "report.pdf", "0", "true", "true"],
        ["req2.txt", "malicious999", "../../../etc/passwd", "1", "false", "true"],
        ["req3.txt", "legit888", "image.png", "0", "true", "false"]
    ]

    with open("/home/user/final_audit.csv", "r", newline="") as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if row] # ignore empty lines

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, but got {len(actual_rows)}."

    for i, (expected, actual) in enumerate(zip(expected_rows, actual_rows)):
        assert actual == expected, f"Row {i} in CSV does not match expected. Expected: {expected}, Actual: {actual}"


def test_audit_parser_exists():
    assert os.path.isfile("/home/user/audit_parser.c"), "/home/user/audit_parser.c is missing."
    assert os.path.isfile("/home/user/audit_parser"), "Compiled executable /home/user/audit_parser is missing."
    assert os.access("/home/user/audit_parser", os.X_OK), "/home/user/audit_parser is not executable."


def test_generate_audit_script_exists():
    assert os.path.isfile("/home/user/generate_audit.sh"), "/home/user/generate_audit.sh is missing."


def make_request(session, filename):
    return (
        "POST /upload HTTP/1.1\r\n"
        "Host: verifier.example\r\n"
        f"Cookie: session_id={session}\r\n"
        "Content-Type: multipart/form-data; boundary=verify-boundary\r\n"
        "\r\n"
        "--verify-boundary\r\n"
        f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
        "Content-Type: application/octet-stream\r\n"
        "\r\nbody\r\n--verify-boundary--\r\n"
    )


def run_parser(binary, request_text):
    fd, request_path = tempfile.mkstemp(prefix="audit-request-", suffix=".txt")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(request_text.encode("utf-8"))
        return subprocess.run(
            [binary, request_path], capture_output=True, text=True, timeout=10
        )
    finally:
        os.unlink(request_path)


def test_parser_is_elf_and_handles_unseen_requests():
    with open(PARSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_parser must be a compiled executable."

    token = secrets.token_hex(10)
    cases = [
        (f"session_{token}", f"ordinary_{token}.txt", "0"),
        (f"other_{token}", f"folder/../secret_{token}.dat", "1"),
        (f"third_{token}", f"subdir/image_{token}.png", "0"),
    ]
    for session, filename, traversal in cases:
        result = run_parser(PARSER, make_request(session, filename))
        assert result.returncode == 0, result.stderr
        assert result.stdout == f"{session},{filename},{traversal}\n"


def test_c_source_compiles_and_implements_parser():
    with tempfile.TemporaryDirectory(prefix="compile-audit-") as td:
        rebuilt = os.path.join(td, "audit_parser")
        compiled = subprocess.run(
            ["gcc", "-std=c11", PARSER_SOURCE, "-o", rebuilt],
            capture_output=True, text=True, timeout=20
        )
        assert compiled.returncode == 0, compiled.stderr

        token = secrets.token_hex(12)
        for session, filename, traversal in [
            (f"rebuilt_{token}", f"safe_{token}.bin", "0"),
            (f"walk_{token}", f"../../private_{token}.bin", "1"),
        ]:
            result = run_parser(rebuilt, make_request(session, filename))
            assert result.returncode == 0, result.stderr
            assert result.stdout == f"{session},{filename},{traversal}\n"


def test_z_generate_script_computes_fresh_audit_and_invokes_parser():
    syntax = subprocess.run(["bash", "-n", SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, syntax.stderr

    with tempfile.TemporaryDirectory(prefix="audit-verifier-") as backup:
        data_backup = os.path.join(backup, "audit_data")
        parser_backup = os.path.join(backup, "audit_parser")
        final_backup = os.path.join(backup, "final_audit.csv")
        marker = os.path.join(backup, "parser-invocations")
        shutil.copytree(AUDIT_DATA, data_backup)
        shutil.copy2(PARSER, parser_backup)
        had_final = os.path.exists(FINAL_CSV)
        if had_final:
            shutil.copy2(FINAL_CSV, final_backup)

        try:
            token = secrets.token_hex(10)
            sessions = [f"freshA_{token}", f"freshB_{token}", f"freshC_{token}"]
            filenames = [
                f"report_{token}.dat",
                f"../../vault_{token}.dat",
                f"nested/image_{token}.png",
            ]
            basenames = [os.path.basename(x) for x in filenames]
            payloads = [
                f"first payload {token}\n".encode(),
                f"second payload {token}\n".encode(),
                f"third payload {token}\n".encode(),
            ]

            requests_dir = os.path.join(AUDIT_DATA, "requests")
            uploads_dir = os.path.join(AUDIT_DATA, "uploads")
            shutil.rmtree(requests_dir)
            shutil.rmtree(uploads_dir)
            os.makedirs(requests_dir)
            os.makedirs(uploads_dir)

            for i in range(3):
                with open(os.path.join(requests_dir, f"req{i + 1}.txt"), "wb") as f:
                    f.write(make_request(sessions[i], filenames[i]).encode())
                with open(os.path.join(uploads_dir, basenames[i]), "wb") as f:
                    f.write(payloads[i])

            hashes = [hashlib.sha256(x).hexdigest() for x in payloads]
            with open(os.path.join(AUDIT_DATA, "manifest.txt"), "w") as f:
                f.write(f"{hashes[0]}  {basenames[0]}\n")
                f.write(f"{'0' * 64}  {basenames[1]}\n")
                f.write(f"{hashes[2]}  {basenames[2]}\n")

            proxy_source = os.path.join(backup, "proxy.c")
            with open(proxy_source, "w") as f:
                f.write(
                    "#include <stdio.h>\n"
                    "#include <unistd.h>\n"
                    "int main(int argc, char **argv) {\n"
                    f"  FILE *m = fopen(\"{marker}\", \"a\");\n"
                    "  if (m) { fputs(\"called\\n\", m); fclose(m); }\n"
                    f"  execv(\"{parser_backup}\", argv);\n"
                    "  return 127;\n"
                    "}\n"
                )
            proxy_build = subprocess.run(
                ["gcc", proxy_source, "-o", PARSER],
                capture_output=True, text=True, timeout=20
            )
            assert proxy_build.returncode == 0, proxy_build.stderr

            result = subprocess.run(
                ["bash", SCRIPT], capture_output=True, text=True, timeout=30
            )
            assert result.returncode == 0, result.stdout + result.stderr
            assert os.path.isfile(marker), "generate_audit.sh did not invoke /home/user/audit_parser"
            with open(marker) as f:
                assert len(f.readlines()) >= 3, "The parser was not invoked for every request."

            cert_valid = []
            ca = os.path.join(AUDIT_DATA, "certs", "ca.pem")
            for i in range(3):
                cert = os.path.join(AUDIT_DATA, "certs", f"req{i + 1}.pem")
                verified = subprocess.run(
                    ["openssl", "verify", "-CAfile", ca, cert],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                ).returncode == 0
                cert_valid.append("true" if verified else "false")

            expected = [
                ["Request", "SessionID", "Filename", "TraversalAttempt", "CertValid", "HashMatch"],
                ["req1.txt", sessions[0], filenames[0], "0", cert_valid[0], "true"],
                ["req2.txt", sessions[1], filenames[1], "1", cert_valid[1], "false"],
                ["req3.txt", sessions[2], filenames[2], "0", cert_valid[2], "true"],
            ]
            with open(FINAL_CSV, newline="") as f:
                actual = [row for row in csv.reader(f) if row]
            assert actual == expected, f"Fresh audit mismatch. Expected {expected}, got {actual}"
        finally:
            shutil.rmtree(AUDIT_DATA, ignore_errors=True)
            shutil.copytree(data_backup, AUDIT_DATA)
            if os.path.exists(PARSER):
                os.unlink(PARSER)
            shutil.copy2(parser_backup, PARSER)
            if had_final:
                shutil.copy2(final_backup, FINAL_CSV)
            elif os.path.exists(FINAL_CSV):
                os.unlink(FINAL_CSV)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
