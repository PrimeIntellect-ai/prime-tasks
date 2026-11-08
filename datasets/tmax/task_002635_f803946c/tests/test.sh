#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

EXECUTABLE = "/home/user/sre_monitor"
SOURCE = "/home/user/sre_monitor.cpp"
LOG_FILE = "/home/user/system_status.log"
FSTAB_FILE = "/home/user/sys_config/fstab"
ROUTES_FILE = "/home/user/sys_config/routes"
TOKYO = ZoneInfo("Asia/Tokyo")


def run_and_read():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    before = datetime.now(TOKYO)
    result = subprocess.run([EXECUTABLE], capture_output=True, text=True)
    after = datetime.now(TOKYO)
    assert result.returncode == 0, f"Running {EXECUTABLE} failed with error: {result.stderr}"
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not generated."
    with open(LOG_FILE, "r") as f:
        lines = f.read().splitlines()
    return lines, before, after


def assert_current_tokyo_time(line, before, after):
    assert re.fullmatch(r"Time: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} JST", line), \
        f"Time line format is incorrect: {line}"
    parsed = datetime.strptime(line, "Time: %Y-%m-%d %H:%M:%S JST").replace(tzinfo=TOKYO)
    assert before - timedelta(seconds=2) <= parsed <= after + timedelta(seconds=2), \
        f"Time is not the current Asia/Tokyo time: {line}"


def test_00_executable_exists_and_runnable_and_is_built_from_source():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."

    rebuilt = EXECUTABLE + ".verifier-build"
    result = subprocess.run(["g++", SOURCE, "-o", rebuilt], capture_output=True, text=True)
    assert result.returncode == 0, f"Compiling {SOURCE} failed: {result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    os.replace(rebuilt, EXECUTABLE)


def test_log_file_generated_and_format_correct():
    lines, before, after = run_and_read()
    nonempty = [line.strip() for line in lines if line.strip()]

    assert len(nonempty) >= 3, "Log file does not contain enough lines."

    time_match = re.match(r"^Time:\s+\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} JST$", nonempty[0])
    assert time_match, f"Time line format is incorrect: {nonempty[0]}"
    assert_current_tokyo_time(nonempty[0], before, after)

    assert nonempty[1] == "Gateway: 10.0.2.1", f"Gateway line is incorrect: {nonempty[1]}"

    mounts_line = nonempty[2].replace(" ", "")
    assert mounts_line == "EXT4Mounts:/,/var/log", f"EXT4 Mounts line is incorrect: {nonempty[2]}"


def test_no_hardcoding():
    with open(FSTAB_FILE, "r") as f:
        original_fstab = f.read()
    with open(ROUTES_FILE, "r") as f:
        original_routes = f.read()

    new_fstab = """# /etc/fstab
UUID=abc /new_root ext4 defaults 0 1
UUID=def /data ext4 defaults 0 2
UUID=ghi /swap swap sw 0 0
"""
    new_routes = """Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         192.168.1.1     0.0.0.0         UG    100    0        0 eth0
"""

    try:
        with open(FSTAB_FILE, "w") as f:
            f.write(new_fstab)
        with open(ROUTES_FILE, "w") as f:
            f.write(new_routes)

        lines, before, after = run_and_read()
        nonempty = [line.strip() for line in lines if line.strip()]

        assert len(nonempty) >= 3, "Log file does not contain enough lines after modifying configs."
        assert_current_tokyo_time(nonempty[0], before, after)
        assert nonempty[1] == "Gateway: 192.168.1.1", \
            f"Gateway line is hardcoded or incorrectly parsed: {nonempty[1]}"

        mounts_line = nonempty[2].replace(" ", "")
        assert mounts_line == "EXT4Mounts:/new_root,/data", \
            f"EXT4 Mounts line is hardcoded or incorrectly parsed: {nonempty[2]}"
    finally:
        with open(FSTAB_FILE, "w") as f:
            f.write(original_fstab)
        with open(ROUTES_FILE, "w") as f:
            f.write(original_routes)


def test_randomized_configuration_parsing_and_current_time():
    with open(FSTAB_FILE, "r") as f:
        original_fstab = f.read()
    with open(ROUTES_FILE, "r") as f:
        original_routes = f.read()

    rng = secrets.SystemRandom()
    try:
        for _ in range(5):
            entries = []
            for _ in range(rng.randint(1, 4)):
                mount = "/m_" + secrets.token_hex(5)
                entries.append(("UUID=" + secrets.token_hex(8), mount, "ext4"))
            for _ in range(rng.randint(1, 3)):
                mount = "/n_" + secrets.token_hex(5)
                entries.append(("UUID=" + secrets.token_hex(8), mount, rng.choice(["xfs", "vfat", "swap"])))
            rng.shuffle(entries)
            expected_mounts = [mount for _, mount, fs_type in entries if fs_type == "ext4"]

            fstab_lines = ["# generated fixture " + secrets.token_hex(4)]
            for device, mount, fs_type in entries:
                sep = rng.choice([" ", "  ", "\t"])
                fstab_lines.append(sep.join([device, mount, fs_type, "defaults", "0", "2"]))
            fstab_text = "\n".join(fstab_lines) + "\n"

            gateway = f"{rng.randint(11, 223)}.{rng.randint(0, 255)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"
            route_rows = [
                ("0.0.0.0", gateway, "0.0.0.0", "UG", "eth" + str(rng.randint(0, 9))),
                (f"10.{rng.randint(0, 255)}.{rng.randint(0, 255)}.0", "0.0.0.0", "255.255.255.0", "U", "eth7"),
                (f"172.{rng.randint(16, 31)}.{rng.randint(0, 255)}.0", "0.0.0.0", "255.255.255.0", "U", "eth8"),
            ]
            rng.shuffle(route_rows)
            route_lines = [
                "Kernel IP routing table",
                "Destination Gateway Genmask Flags Metric Ref Use Iface",
            ]
            for destination, row_gateway, mask, flags, iface in route_rows:
                sep = rng.choice([" ", "   ", "\t"])
                route_lines.append(sep.join([destination, row_gateway, mask, flags, "100", "0", "0", iface]))
            routes_text = "\n".join(route_lines) + "\n"

            with open(FSTAB_FILE, "w") as f:
                f.write(fstab_text)
            with open(ROUTES_FILE, "w") as f:
                f.write(routes_text)

            lines, before, after = run_and_read()
            assert len(lines) == 3, f"Log must contain exactly three lines, got: {lines}"
            assert_current_tokyo_time(lines[0], before, after)
            assert lines[1] == "Gateway: " + gateway, f"Incorrect gateway for generated fixture: {lines[1]}"
            assert lines[2] == "EXT4 Mounts: " + ",".join(expected_mounts), \
                f"Incorrect mount list for generated fixture: {lines[2]}"
    finally:
        with open(FSTAB_FILE, "w") as f:
            f.write(original_fstab)
        with open(ROUTES_FILE, "w") as f:
            f.write(original_routes)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
