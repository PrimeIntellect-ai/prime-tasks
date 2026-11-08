#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

SCRIPT_PATH = "/home/user/analyze_malware.sh"
MALWARE_PATH = "/home/user/malware.elf"
OUTPUT_PATHS = [
    "/home/user/extracted_cert.pem",
    "/home/user/cert_info.txt",
    "/home/user/c2_url.txt",
]


def run_script():
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Analysis script failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def remove_outputs():
    for path in OUTPUT_PATHS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def openssl_info(cert_path):
    result = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-subject"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def extract_embedded_cert(binary_path):
    with tempfile.TemporaryDirectory() as td:
        output = os.path.join(td, "section.bin")
        result = subprocess.run(
            ["objcopy", "--dump-section", f".c2_cert={output}", binary_path],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, result.stderr
        with open(output, "rb") as f:
            return f.read()


def derive_c2_url(binary_path):
    result = subprocess.run(["strings", binary_path], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    match = re.search(
        r"JWT:alg=none\|CSP:[^\n]*?connect-src\s+([^;\s]+)",
        result.stdout,
    )
    assert match, "Could not derive the connect-src URL from malware.elf"
    return match.group(1)


def test_analyze_malware_script_exists_and_executable():
    script_path = "/home/user/analyze_malware.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_actually_analyzes_the_current_elf():
    with open(MALWARE_PATH, "rb") as f:
        original_binary = f.read()
    original_mode = stat.S_IMODE(os.stat(MALWARE_PATH).st_mode)

    token = uuid.uuid4().hex
    expected_url = f"https://c2-{token}.evil-server.local"

    with tempfile.TemporaryDirectory() as td:
        cert_path = os.path.join(td, "cert.pem")
        key_path = os.path.join(td, "key.pem")
        source_path = os.path.join(td, "variant.c")
        binary_path = os.path.join(td, "variant.elf")

        cert_result = subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", key_path, "-out", cert_path, "-days", "1", "-nodes",
                "-subj", f"/C=US/O=Verifier/CN=c2-{token}.evil-server.local",
            ],
            capture_output=True,
            text=True,
        )
        assert cert_result.returncode == 0, cert_result.stderr

        payload = (
            "JWT:alg=none|CSP:default-src 'none';"
            f"connect-src {expected_url};frame-ancestors 'none'"
        )
        with open(source_path, "w") as f:
            f.write(
                '#include <stdio.h>\n'
                f'const char *payload = "{payload}";\n'
                'int main(void) { puts("variant"); return 0; }\n'
            )

        compile_result = subprocess.run(
            ["gcc", "-o", binary_path, source_path],
            capture_output=True,
            text=True,
        )
        assert compile_result.returncode == 0, compile_result.stderr

        objcopy_result = subprocess.run(
            [
                "objcopy", "--add-section", f".c2_cert={cert_path}",
                "--set-section-flags", ".c2_cert=alloc,readonly", binary_path,
            ],
            capture_output=True,
            text=True,
        )
        assert objcopy_result.returncode == 0, objcopy_result.stderr

        with open(binary_path, "rb") as f:
            variant_binary = f.read()
        with open(cert_path, "rb") as f:
            expected_cert = f.read()
        expected_info = openssl_info(cert_path)

    variant_error = None
    try:
        with open(MALWARE_PATH, "wb") as f:
            f.write(variant_binary)
        os.chmod(MALWARE_PATH, original_mode)
        remove_outputs()

        try:
            run_script()
            with open("/home/user/extracted_cert.pem", "rb") as f:
                assert f.read() == expected_cert, (
                    "extracted_cert.pem was not extracted from the current "
                    ".c2_cert section"
                )
            with open("/home/user/cert_info.txt", "r") as f:
                assert f.read() == expected_info, (
                    "cert_info.txt is not the exact OpenSSL issuer/subject output "
                    "for the embedded certificate"
                )
            with open("/home/user/c2_url.txt", "r") as f:
                assert f.read().strip() == expected_url, (
                    "c2_url.txt was not derived from the current CSP connect-src directive"
                )
        except Exception as exc:
            variant_error = exc
    finally:
        with open(MALWARE_PATH, "wb") as f:
            f.write(original_binary)
        os.chmod(MALWARE_PATH, original_mode)
        remove_outputs()
        run_script()

    if variant_error is not None:
        raise variant_error


def test_extracted_cert_pem():
    cert_path = "/home/user/extracted_cert.pem"
    assert os.path.isfile(cert_path), f"File {cert_path} does not exist."

    # Check if it's a valid cert using openssl
    result = subprocess.run(['openssl', 'x509', '-in', cert_path, '-noout'], capture_output=True, text=True)
    assert result.returncode == 0, f"{cert_path} is not a valid certificate. OpenSSL error: {result.stderr}"


def test_cert_info_txt():
    info_path = "/home/user/cert_info.txt"
    assert os.path.isfile(info_path), f"File {info_path} does not exist."

    with open(info_path, 'r') as f:
        content = f.read()

    # Check for expected issuer and subject
    assert "issuer=" in content and "c2.evil-server.local" in content, "cert_info.txt does not contain the correct issuer information."
    assert "subject=" in content and "c2.evil-server.local" in content, "cert_info.txt does not contain the correct subject information."


def test_c2_url_txt():
    url_path = "/home/user/c2_url.txt"
    assert os.path.isfile(url_path), f"File {url_path} does not exist."

    with open(url_path, 'r') as f:
        content = f.read().strip()

    assert content == "https://c2.evil-server.local", f"Expected 'https://c2.evil-server.local' in {url_path}, but found '{content}'."


def test_outputs_are_derived_from_original_malware():
    expected_cert = extract_embedded_cert(MALWARE_PATH)
    with open("/home/user/extracted_cert.pem", "rb") as f:
        assert f.read() == expected_cert

    expected_info = openssl_info("/home/user/extracted_cert.pem")
    with open("/home/user/cert_info.txt", "r") as f:
        assert f.read() == expected_info

    expected_url = derive_c2_url(MALWARE_PATH)
    with open("/home/user/c2_url.txt", "r") as f:
        assert f.read().strip() == expected_url
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
