#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import ssl
import subprocess
import urllib.error
import urllib.request
import uuid

HOME = "/home/user"
ORIGINAL_PATHS = [
    "/healthz",
    "/api/v1/users",
    "/metrics",
    "/api/v2/missing",
]
ORIGINAL_CSV = [
    "/healthz,200",
    "/api/v1/users,404",
    "/metrics,200",
    "/api/v2/missing,404",
]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def request_status(path):
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    request = urllib.request.Request("https://127.0.0.1:8443" + path)
    try:
        with urllib.request.urlopen(request, context=context, timeout=3) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def run_checker(executable, expected):
    report = os.path.join(HOME, "status_report.csv")
    if os.path.exists(report):
        os.remove(report)
    result = subprocess.run(
        [executable], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(report), f"{executable} did not create status_report.csv"
    assert read_nonempty_lines(report) == expected, (
        f"{executable} produced an incorrect status_report.csv"
    )


def test_www_directory_and_files():
    assert os.path.isdir("/home/user/www"), "/home/user/www directory is missing"

    healthz_path = "/home/user/www/healthz"
    assert os.path.isfile(healthz_path), f"{healthz_path} is missing"
    with open(healthz_path, "r") as f:
        assert f.read().strip() == "OK", f"Content of {healthz_path} is incorrect"

    metrics_path = "/home/user/www/metrics"
    assert os.path.isfile(metrics_path), f"{metrics_path} is missing"
    with open(metrics_path, "r") as f:
        assert f.read().strip() == "prometheus", f"Content of {metrics_path} is incorrect"


def test_tls_certificates():
    cert = "/home/user/cert.pem"
    key = "/home/user/key.pem"
    assert os.path.isfile(cert), "/home/user/cert.pem is missing"
    assert os.path.isfile(key), "/home/user/key.pem is missing"

    decoded = ssl._ssl._test_decode_cert(cert)
    common_names = [
        value
        for rdn in decoded.get("subject", ())
        for name, value in rdn
        if name == "commonName"
    ]
    assert common_names == ["localhost"], "Certificate CN must be localhost"

    with open(key, "rb") as f:
        key_data = f.read()
    assert b"ENCRYPTED" not in key_data.upper(), "Private key is encrypted"
    result = subprocess.run(
        ["openssl", "pkey", "-in", key, "-noout", "-check"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5
    )
    assert result.returncode == 0, "Private key is invalid or requires a passphrase"


def test_web_server_running():
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request("https://127.0.0.1:8443/healthz")
        with urllib.request.urlopen(req, context=context, timeout=2) as response:
            assert response.status == 200, "Web server did not return 200 for /healthz"
            assert response.read().decode("utf-8").strip() == "OK", "Web server returned incorrect content for /healthz"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to web server on 127.0.0.1:8443: {e}"


def test_clean_paths_file():
    path_file = "/home/user/clean_paths.txt"
    assert os.path.isfile(path_file), f"{path_file} is missing"
    assert read_nonempty_lines(path_file) == ORIGINAL_PATHS, (
        f"Content of {path_file} does not match expected paths"
    )


def test_c_checker_files_and_libcurl():
    source = "/home/user/checker.c"
    executable = "/home/user/checker"
    assert os.path.isfile(source), "/home/user/checker.c is missing"
    assert os.path.isfile(executable), "/home/user/checker executable is missing"
    assert os.access(executable, os.X_OK), "/home/user/checker is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/checker is not a compiled ELF executable"

    with open(source, "r", errors="replace") as f:
        source_text = f.read()
    assert re.search(r"\bcurl_(easy|multi)_", source_text), "checker.c does not use the libcurl API"
    assert "CURLOPT_SSL_VERIFYPEER" in source_text, "checker.c does not configure SSL peer verification"
    assert "CURLOPT_SSL_VERIFYHOST" in source_text, "checker.c does not configure SSL host verification"

    compiled = "/tmp/checker_from_source"
    result = subprocess.run(
        ["gcc", source, "-o", compiled, "-lcurl"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, f"checker.c does not compile with libcurl: {result.stderr}"
    linked = subprocess.run(
        ["ldd", compiled], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5
    )
    assert linked.returncode == 0 and "libcurl" in linked.stdout, (
        "Compiled checker.c is not linked to libcurl"
    )


def test_status_report_csv():
    csv_file = "/home/user/status_report.csv"
    assert os.path.isfile(csv_file), f"{csv_file} is missing"
    assert read_nonempty_lines(csv_file) == ORIGINAL_CSV, (
        f"Content of {csv_file} is incorrect"
    )


def test_z_checker_execution_on_derived_inputs():
    clean_file = os.path.join(HOME, "clean_paths.txt")
    report_file = os.path.join(HOME, "status_report.csv")
    compiled = "/tmp/checker_from_source"
    token = uuid.uuid4().hex
    present_path = f"/verifier_{token}"
    missing_path = f"/missing_{token}"
    present_file = os.path.join(HOME, "www", present_path.lstrip("/"))

    old_clean = open(clean_file, "rb").read()
    old_report = open(report_file, "rb").read() if os.path.exists(report_file) else None
    try:
        with open(present_file, "w") as f:
            f.write("dynamic verifier content\n")

        paths = [present_path, missing_path, "/healthz", "/metrics"]
        with open(clean_file, "w") as f:
            f.write("\n".join(paths) + "\n")

        statuses = [request_status(path) for path in paths]
        assert statuses[0] == 200 and statuses[1] == 404, (
            "The HTTPS server is not serving the requested www directory"
        )
        expected = [f"{path},{status}" for path, status in zip(paths, statuses)]

        run_checker("/home/user/checker", expected)
        run_checker(compiled, expected)
    finally:
        with open(clean_file, "wb") as f:
            f.write(old_clean)
        if old_report is not None:
            with open(report_file, "wb") as f:
                f.write(old_report)
        elif os.path.exists(report_file):
            os.remove(report_file)
        if os.path.exists(present_file):
            os.remove(present_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
