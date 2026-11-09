#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile

GO_SRC = "/home/user/net_troubleshooter.go"
GO_BIN = "/home/user/net_troubleshooter"
FSTAB = "/home/user/fstab.conf"
QEMU_OPTS = "/home/user/qemu.opts"
ALERT = "/home/user/mailspool/alert.eml"
SERVICE = "/home/user/.config/systemd/user/net-watcher.service"


def expected_email(count, port):
    return f"""To: admin@local
Subject: Network Alert

Connection lost {count} times.
VNC Port: {port}"""


def run_and_check(binary, count, display):
    os.makedirs(os.path.dirname(ALERT), exist_ok=True)
    with open(ALERT, "w") as f:
        f.write("stale alert that must be overwritten")

    result = subprocess.run([binary], capture_output=True, timeout=15)
    expected_code = 1 if count > 0 else 0
    assert result.returncode == expected_code, (
        f"Expected exit code {expected_code}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    if count > 0:
        assert os.path.isfile(ALERT), f"Alert file was not created at {ALERT}"
        with open(ALERT, "r") as f:
            content = f.read().strip()
        expected = expected_email(count, 5900 + display)
        assert content == expected, (
            f"Alert file content does not match expected format.\n"
            f"Expected:\n{expected}\nGot:\n{content}"
        )


def write_fixture(mount_point, count, display):
    os.makedirs(mount_point, exist_ok=True)
    with open(FSTAB, "w") as f:
        f.write("# dynamically generated fixture\n")
        f.write(f"/dev/vdb10 {mount_point}-wrong ext4 defaults 0 0\n")
        f.write("/dev/vda1 / ext4 defaults 1 1\n")
        f.write(f"/dev/vdb1\t{mount_point} ext4 ro,nofail 0 2\n")
        f.write("/dev/vdc1 /mnt/unrelated xfs defaults 0 0\n")

    with open(os.path.join(mount_point, "network.log"), "w") as f:
        f.write("[00:00] INFO: test start\n")
        for i in range(count):
            f.write(f"[{i:02d}:10] ERROR: CONNECTIVITY_LOST\n")
            f.write(f"[{i:02d}:11] INFO: retrying\n")
        f.write("[23:59] INFO: test end\n")

    with open(QEMU_OPTS, "w") as f:
        f.write(
            f"-m 1024 -drive file=test.qcow2 -vnc 127.0.0.1:{display} "
            "-netdev user,id=n1 -device virtio-net,netdev=n1\n"
        )


def test_go_files_exist_and_source_compiles():
    assert os.path.isfile(GO_SRC), f"Go source file missing: {GO_SRC}"
    assert os.path.isfile(GO_BIN), f"Compiled Go binary missing: {GO_BIN}"
    assert os.access(GO_BIN, os.X_OK), f"Go binary is not executable: {GO_BIN}"

    with open(GO_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled binary is not an ELF executable"

    version = subprocess.run(
        ["go", "version", "-m", GO_BIN], capture_output=True, text=True, timeout=15
    )
    assert version.returncode == 0 and re.search(r"\bgo1\.[0-9]+", version.stdout), (
        "The installed executable does not contain Go build information"
    )

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/net_troubleshooter_rebuilt", GO_SRC],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Go source does not compile:\n{build.stderr}"


def test_go_program_execution_and_output():
    # Preserve the original fixed-fixture assertions.
    if os.path.exists(ALERT):
        os.remove(ALERT)
    result = subprocess.run([GO_BIN], capture_output=True, timeout=15)
    assert result.returncode == 1, f"Expected exit code 1, got {result.returncode}"
    assert os.path.isfile(ALERT), f"Alert file was not created at {ALERT}"
    with open(ALERT, "r") as f:
        content = f.read().strip()
    expected = expected_email(3, 5907)
    assert content == expected, (
        f"Alert file content does not match expected format.\n"
        f"Expected:\n{expected}\nGot:\n{content}"
    )

    original_fstab = open(FSTAB, "rb").read()
    original_qemu = open(QEMU_OPTS, "rb").read()
    rng = random.SystemRandom()

    try:
        with tempfile.TemporaryDirectory(prefix="net-watcher-") as root:
            # Randomized positive cases prevent a fixed-output executable from passing.
            cases = []
            while len(cases) < 2:
                candidate = (rng.randint(1, 8), rng.randint(0, 40))
                if candidate != (3, 7) and candidate not in cases:
                    cases.append(candidate)

            for index, (count, display) in enumerate(cases):
                mount_point = os.path.join(root, f"logs-{index}")
                write_fixture(mount_point, count, display)
                run_and_check(GO_BIN, count, display)
                run_and_check("/tmp/net_troubleshooter_rebuilt", count, display)

            # Also exercise the required no-error exit path.
            mount_point = os.path.join(root, "logs-zero")
            write_fixture(mount_point, 0, rng.randint(0, 40))
            run_and_check(GO_BIN, 0, 0)
            result = subprocess.run(
                ["/tmp/net_troubleshooter_rebuilt"], capture_output=True, timeout=15
            )
            assert result.returncode == 0, (
                f"Expected rebuilt program to exit 0 for an empty-error log, "
                f"got {result.returncode}"
            )
    finally:
        with open(FSTAB, "wb") as f:
            f.write(original_fstab)
        with open(QEMU_OPTS, "wb") as f:
            f.write(original_qemu)


def parse_unit(path):
    sections = {}
    current = None
    with open(path, "r") as f:
        raw_lines = f.readlines()

    logical_lines = []
    pending = ""
    for raw in raw_lines:
        line = raw.rstrip("\n")
        if pending:
            line = pending + line.lstrip()
        if line.rstrip().endswith("\\"):
            pending = line.rstrip()[:-1]
            continue
        logical_lines.append(line)
        pending = ""
    assert not pending, "Service unit ends with an incomplete continuation"

    for number, raw in enumerate(logical_lines, 1):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            assert current, f"Empty section name on line {number}"
            sections.setdefault(current, {})
            continue
        assert current is not None, f"Directive outside a section on line {number}"
        assert "=" in line, f"Malformed directive on line {number}: {raw!r}"
        key, value = line.split("=", 1)
        key = key.strip()
        assert key, f"Empty directive name on line {number}"
        sections[current].setdefault(key, []).append(value.strip())
    return sections


def test_systemd_service_file():
    assert os.path.isfile(SERVICE), f"Systemd service file missing: {SERVICE}"
    with open(SERVICE, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "ExecStart=/home/user/net_troubleshooter" in content, "Missing or incorrect ExecStart directive"
    assert "Restart=on-failure" in content, "Missing or incorrect Restart directive"
    assert "RestartSec=5" in content, "Missing or incorrect RestartSec directive"
    assert "WantedBy=default.target" in content, "Missing or incorrect WantedBy directive"

    # Ensure those strings are real directives in the proper systemd sections.
    unit = parse_unit(SERVICE)
    assert "Service" in unit, "Missing [Service] section"
    assert "Install" in unit, "Missing [Install] section"
    assert "/home/user/net_troubleshooter" in unit["Service"].get("ExecStart", []), (
        "ExecStart must be in [Service] and run /home/user/net_troubleshooter"
    )
    assert "on-failure" in unit["Service"].get("Restart", []), (
        "Restart=on-failure must be in [Service]"
    )
    assert "5" in unit["Service"].get("RestartSec", []), (
        "RestartSec=5 must be in [Service]"
    )
    assert "default.target" in unit["Install"].get("WantedBy", []), (
        "WantedBy=default.target must be in [Install]"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
