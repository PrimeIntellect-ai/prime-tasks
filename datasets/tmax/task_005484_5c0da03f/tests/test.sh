#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tarfile
import uuid

C_FILE = "/home/user/analyze.c"
EXE_FILE = "/home/user/analyze"
TAR_FILE = "/home/user/config_update.tar"
ALERTS_LOG = "/home/user/alerts.log"
SAFE_LOG = "/home/user/safe_elfs.log"


def clear_logs():
    for path in (ALERTS_LOG, SAFE_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_analyzer(executable):
    clear_logs()
    subprocess.run([executable], cwd="/home/user", check=True, timeout=10)


def read_lines(path):
    assert os.path.exists(path), f"Missing required file: {path}"
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_c_program_exists():
    assert os.path.exists(C_FILE), f"Missing required file: {C_FILE}"
    assert os.path.isfile(C_FILE), f"Expected {C_FILE} to be a file"


def test_executable_exists():
    assert os.path.exists(EXE_FILE), f"Missing executable: {EXE_FILE}. Did you compile the program?"
    assert os.access(EXE_FILE, os.X_OK), f"Expected {EXE_FILE} to be executable"
    with open(EXE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {EXE_FILE} to be a compiled ELF executable"


def test_original_archive_results():
    run_analyzer(EXE_FILE)

    lines = read_lines(ALERTS_LOG)
    expected = ["../../etc/shadow", "/usr/bin/system_update"]
    for exp in expected:
        assert exp in lines, f"Expected '{exp}' to be in {ALERTS_LOG}, but it was missing"
    for line in lines:
        assert line in expected, f"Unexpected file '{line}' found in {ALERTS_LOG}"

    lines = read_lines(SAFE_LOG)
    expected = ["safe_bins/safe_bin.elf"]
    for exp in expected:
        assert exp in lines, f"Expected '{exp}' to be in {SAFE_LOG}, but it was missing"
    for line in lines:
        assert line in expected, f"Unexpected file '{line}' found in {SAFE_LOG}"


def test_analyzer_parses_generated_archive():
    token = "case_" + uuid.uuid4().hex
    entries = [
        (f"{token}/config.txt", b"configuration=true\n"),
        (f"{token}/bin/payload", b"\x7fELF" + os.urandom(37)),
        (f"{token}/short", b"\x7fEL"),
        (f"{token}/..hidden/data", b"\x7fELF" + os.urandom(11)),
        (f"{token}/../escape.txt", b"not an executable"),
        (f"{token}/x../caught.bin", b"\x7fELF" + os.urandom(19)),
        (f"/{token}/absolute.bin", b"\x7fELF" + os.urandom(23)),
    ]

    expected_alerts = [
        name for name, payload in entries
        if name.startswith("/") or "../" in name
    ]
    expected_safe = [
        name for name, payload in entries
        if not (name.startswith("/") or "../" in name) and payload[:4] == b"\x7fELF"
    ]

    with open(TAR_FILE, "rb") as f:
        original_tar = f.read()

    rebuilt = "/tmp/analyze_rebuilt"
    subprocess.run(["gcc", C_FILE, "-o", rebuilt], check=True, timeout=20)
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Freshly compiled analyze.c did not produce an ELF executable"

    try:
        with tarfile.open(TAR_FILE, "w", format=tarfile.USTAR_FORMAT) as archive:
            for name, payload in entries:
                info = tarfile.TarInfo(name=name)
                info.size = len(payload)
                import io
                archive.addfile(info, io.BytesIO(payload))

        for executable in (EXE_FILE, rebuilt):
            run_analyzer(executable)
            alerts = read_lines(ALERTS_LOG)
            safe_elfs = read_lines(SAFE_LOG)
            assert sorted(alerts) == sorted(expected_alerts), (
                f"{executable} produced incorrect traversal alerts: {alerts}"
            )
            assert sorted(safe_elfs) == sorted(expected_safe), (
                f"{executable} produced incorrect safe ELF results: {safe_elfs}"
            )
    finally:
        with open(TAR_FILE, "wb") as f:
            f.write(original_tar)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
