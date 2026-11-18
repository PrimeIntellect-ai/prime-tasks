#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import shutil
import subprocess
import tarfile
import uuid

import pytest

SCRIPT = "/home/user/run_tester.sh"
SOURCE = "/home/user/restore_tester.go"
BINARY = "/home/user/restore_tester"
BACKUPS = "/home/user/backups"
LOG = "/home/user/restore_results.log"
TMP_RESTORE = "/home/user/tmp_restore"


def read_log():
    assert os.path.isfile(LOG), f"{LOG} was not created."
    with open(LOG, "r", encoding="utf-8") as f:
        return f.read().strip().splitlines()


def add_bytes(tf, arcname, data):
    info = tarfile.TarInfo(arcname)
    info.size = len(data)
    info.mode = 0o644
    tf.addfile(info, io.BytesIO(data))


def create_cases(tag):
    shutil.rmtree(BACKUPS, ignore_errors=True)
    os.makedirs(BACKUPS, exist_ok=True)

    cases = {
        f"{tag}_a_valid.tar.gz": ("meta", b'{"status":"ok","extra":true}'),
        f"{tag}_b_wrong.tar.gz": ("meta", b'{"status":"corrupt"}'),
        f"{tag}_c_invalid_json.tar.gz": ("meta", b'{not-json'),
        f"{tag}_d_missing.tar.gz": ("missing", b"payload"),
        f"{tag}_e_nested_only.tar.gz": ("nested", b'{"status":"ok"}'),
        f"{tag}_f_non_string.tar.gz": ("meta", b'{"status":true}'),
        f"{tag}_g_bad_archive.tar.gz": ("corrupt_archive", b"not a gzip archive"),
    }

    expected = []
    for filename, (kind, data) in cases.items():
        path = os.path.join(BACKUPS, filename)
        if kind == "corrupt_archive":
            with open(path, "wb") as f:
                f.write(data)
        else:
            with tarfile.open(path, "w:gz") as tf:
                if kind == "meta":
                    add_bytes(tf, "meta.json", data)
                elif kind == "nested":
                    add_bytes(tf, "nested/meta.json", data)
                else:
                    add_bytes(tf, "data.txt", data)
        status = "SUCCESS" if kind == "meta" and b'\"status\":\"ok\"' in data else "FAILED"
        expected.append(f"{filename},{status}")

    return sorted(expected)


def prepare_run():
    if os.path.exists(LOG):
        os.remove(LOG)
    shutil.rmtree(TMP_RESTORE, ignore_errors=True)
    os.makedirs(TMP_RESTORE, exist_ok=True)
    with open(os.path.join(TMP_RESTORE, "stale-file"), "w", encoding="utf-8") as f:
        f.write("must be removed")


def run_and_check(command, expected):
    prepare_run()
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, (
        f"{command} failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert read_log() == expected
    assert not os.path.exists(TMP_RESTORE), f"Temporary directory {TMP_RESTORE} was not cleaned up."


def test_run_tester_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."


def test_original_archives_and_results():
    result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        if os.path.isfile(LOG) and open(LOG, encoding="utf-8").read().strip() == "BUILD_FAILED":
            pytest.fail("Go build failed as indicated by BUILD_FAILED in restore_results.log.")
        pytest.fail(f"{SCRIPT} failed with exit code {result.returncode}. Output: {result.stderr}")

    expected_lines = [
        "backup_a.tar.gz,SUCCESS",
        "backup_b.tar.gz,FAILED",
        "backup_c.tar.gz,FAILED",
    ]
    assert read_log() == expected_lines
    assert not os.path.exists(TMP_RESTORE), f"Temporary directory {TMP_RESTORE} was not cleaned up."


def test_dynamic_archives_wrapper_binary_and_source():
    # Exercise the wrapper on archive names and contents generated only at verification time.
    expected_one = create_cases("case_" + uuid.uuid4().hex)
    if os.path.exists(BINARY):
        os.remove(BINARY)
    run_and_check([SCRIPT], expected_one)

    assert os.path.isfile(BINARY), "The wrapper did not create /home/user/restore_tester."
    assert os.access(BINARY, os.X_OK), "The built restore_tester is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The wrapper output is not a compiled executable."

    # Change all inputs, then invoke the wrapper-built artifact directly.
    expected_two = create_cases("binary_" + uuid.uuid4().hex)
    run_and_check([BINARY], expected_two)

    # Independently compile the submitted Go source and exercise that artifact too.
    verifier_binary = "/tmp/verifier_restore_tester"
    if os.path.exists(verifier_binary):
        os.remove(verifier_binary)
    build = subprocess.run(
        ["go", "build", "-o", verifier_binary, SOURCE],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Submitted Go source did not build: {build.stderr}"
    expected_three = create_cases("source_" + uuid.uuid4().hex)
    run_and_check([verifier_binary], expected_three)


def test_wrapper_build_failure_contract():
    with open(SOURCE, "rb") as f:
        original_source = f.read()
    original_mode = os.stat(SOURCE).st_mode
    try:
        with open(SOURCE, "wb") as f:
            f.write(b"package main\nfunc main( {\n")
        os.chmod(SOURCE, original_mode)
        if os.path.exists(BINARY):
            os.remove(BINARY)
        if os.path.exists(LOG):
            os.remove(LOG)

        result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=60)
        assert result.returncode == 1, f"Build failure must exit 1, got {result.returncode}."
        assert os.path.isfile(LOG), "Build failure did not create restore_results.log."
        with open(LOG, "rb") as f:
            assert f.read() == b"BUILD_FAILED\n", "Build failure log must contain exactly one BUILD_FAILED line."
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        os.chmod(SOURCE, original_mode)
        shutil.rmtree(TMP_RESTORE, ignore_errors=True)


def test_cron_conf():
    cron_path = "/home/user/cron.conf"
    assert os.path.isfile(cron_path), f"{cron_path} does not exist."
    with open(cron_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    pattern = r"^(?:\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*\s+/home/user/run_tester\.sh$"
    match = False
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if re.match(pattern, line):
            match = True
            break
    assert match, f"{cron_path} does not contain a valid every-15-minutes cron expression."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
