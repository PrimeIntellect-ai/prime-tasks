#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import secrets
import shutil
import stat
import subprocess

SCRIPT_PATH = "/home/user/bin/rotate_and_test.sh"
RESTORE_ROOT = "/home/user/restore_area"
SUMMARY_PATH = "/home/user/restore_summary.txt"
EXPECTED_LOG = (
    b'192.168.1.1 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 2326\n'
    b'192.168.1.2 - - [10/Oct/2023:13:56:01 -0700] "POST /api HTTP/1.1" 200 102\n'
)


def read_summary():
    assert os.path.isfile(SUMMARY_PATH), f"Summary report not found at {SUMMARY_PATH}"
    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def test_original_final_state():
    config_path = os.path.join(RESTORE_ROOT, "etc/app_config.conf")
    assert os.path.isfile(config_path), (
        f"Configuration file not found at {config_path}. Did you extract the archive?"
    )

    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script at {SCRIPT_PATH} is not executable"

    log_gz_path = os.path.join(RESTORE_ROOT, "var/log/app/access.log.1.gz")
    log_path = os.path.join(RESTORE_ROOT, "var/log/app/access.log")
    assert os.path.isfile(log_gz_path), f"Rotated log file not found at {log_gz_path}"
    assert os.path.isfile(log_path), f"Original log file not found at {log_path}"
    assert os.path.getsize(log_path) == 0, (
        f"Original log file at {log_path} was not truncated (size is not 0)"
    )

    try:
        with gzip.open(log_gz_path, "rb") as f:
            rotated_data = f.read()
    except (OSError, EOFError) as exc:
        raise AssertionError(f"{log_gz_path} is not a valid gzip file: {exc}")
    assert rotated_data == EXPECTED_LOG, "Rotated gzip does not contain the original access log"

    cert_path = os.path.join(RESTORE_ROOT, "etc/certs/app.crt")
    assert os.path.isfile(cert_path), f"Restored certificate not found at {cert_path}"

    assert read_summary() == [
        "RESTORED_PORT=8443",
        "TLS_CERT_FOUND=true",
        "LOG_ROTATED=true",
    ], f"Summary report at {SUMMARY_PATH} does not contain exactly the required lines"


def exercise_script(cert_should_exist):
    token = secrets.token_hex(8)
    port = str(20000 + secrets.randbelow(30000))
    log_rel = f"var/log/verification_{token}"
    cert_rel = f"etc/certs/verification_{token}.crt"
    log_dir = os.path.join(RESTORE_ROOT, log_rel)
    cert_path = os.path.join(RESTORE_ROOT, cert_rel)
    original_data = secrets.token_bytes(97) + b"\nverification-log-" + token.encode() + b"\n"

    shutil.rmtree(RESTORE_ROOT, ignore_errors=True)
    os.makedirs(os.path.join(RESTORE_ROOT, "etc/certs"), exist_ok=True)
    os.makedirs(log_dir, exist_ok=True)

    with open(os.path.join(RESTORE_ROOT, "etc/app_config.conf"), "w", encoding="utf-8") as f:
        f.write(f"PORT={port}\nTLS_CERT={cert_rel}\nLOG_DIR={log_rel}\n")
    with open(os.path.join(log_dir, "access.log"), "wb") as f:
        f.write(original_data)
    if cert_should_exist:
        with open(cert_path, "wb") as f:
            f.write(b"verification certificate\n")

    if os.path.exists(SUMMARY_PATH):
        os.remove(SUMMARY_PATH)

    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}. stderr: "
        f"{result.stderr.decode(errors='replace')}"
    )

    log_path = os.path.join(log_dir, "access.log")
    gzip_path = os.path.join(log_dir, "access.log.1.gz")
    assert os.path.isfile(log_path), "Script removed the original access.log instead of truncating it"
    assert os.path.getsize(log_path) == 0, "Script did not truncate the configured access.log"
    assert os.path.isfile(gzip_path), "Script did not create access.log.1.gz in the configured log directory"
    try:
        with gzip.open(gzip_path, "rb") as f:
            compressed_data = f.read()
    except (OSError, EOFError) as exc:
        raise AssertionError(f"Script output is not a valid gzip file: {exc}")
    assert compressed_data == original_data, "Script did not preserve the access log data in the gzip"

    expected_cert = "true" if cert_should_exist else "false"
    assert read_summary() == [
        f"RESTORED_PORT={port}",
        f"TLS_CERT_FOUND={expected_cert}",
        "LOG_ROTATED=true",
    ], "Script did not generate exactly the required dynamic summary"


def test_script_behavior_on_dynamic_inputs():
    exercise_script(True)
    exercise_script(False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
