#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import pytest

SCRIPT_DIR = "/home/user"
DATA_VOLUME = "/home/user/data_volume"
ROUTES_CONF = "/home/user/routes.conf"
ROUTER_LOG = "/home/user/router.log"
THRESHOLD = 52_428_800
LOW_ROUTE = "10.0.0.0/24 via 192.168.1.1 dev eth0"
HIGH_ROUTE = "10.0.0.0/24 via 192.168.2.254 dev eth1"


def get_script_path():
    for ext in ["sh", "py"]:
        path = os.path.join(SCRIPT_DIR, f"storage_router.{ext}")
        if os.path.exists(path):
            return path
    return None


def clear_data_volume():
    os.makedirs(DATA_VOLUME, exist_ok=True)
    for name in os.listdir(DATA_VOLUME):
        path = os.path.join(DATA_VOLUME, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)


def reset_outputs():
    for path in [ROUTES_CONF, ROUTER_LOG]:
        if os.path.exists(path):
            os.remove(path)


def test_script_exists_and_executable():
    script_path = get_script_path()
    assert script_path is not None, "storage_router script not found in /home/user"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable"


def test_crontab_exists():
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        pytest.fail("crontab for user does not exist or failed to load")

    match = re.search(r"\*/5\s+\*\s+\*\s+\*\s+\*\s+.+storage_router\.(sh|py)", output)
    assert match is not None, "Cron job for storage_router running every 5 minutes not found in crontab"


def create_dummy_file(size_mb, filename):
    filepath = os.path.join(DATA_VOLUME, filename)
    with open(filepath, "wb") as f:
        f.write(b"\0" * (size_mb * 1024 * 1024))
    return filepath


def write_sized_file(path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    block = b"\0" * (1024 * 1024)
    remaining = size
    with open(path, "wb") as f:
        while remaining:
            chunk = min(remaining, len(block))
            f.write(block[:chunk])
            remaining -= chunk


def get_log_lines():
    if not os.path.exists(ROUTER_LOG):
        return []
    with open(ROUTER_LOG, "r") as f:
        return f.readlines()


def assert_route_and_log(expected_route, expected_gateway, expected_lines):
    assert os.path.exists(ROUTES_CONF), "routes.conf was not created"
    with open(ROUTES_CONF, "r") as f:
        content = f.read().strip()
    assert content == expected_route, "routes.conf content does not match the calculated total size"

    lines = get_log_lines()
    assert len(lines) == expected_lines, f"Expected exactly {expected_lines} log line(s)"
    assert re.search(
        rf"\[\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}\] ROUTE_CHANGED: {re.escape(expected_gateway)}",
        lines[-1],
    ), "Log format or gateway is incorrect"


def test_script_behavior():
    script_path = get_script_path()
    if not script_path:
        pytest.fail("Script not found")

    reset_outputs()
    clear_data_volume()

    # Preserve the original fixed checks.
    create_dummy_file(10, "test1.dat")
    subprocess.run([script_path], check=True)

    assert os.path.exists(ROUTES_CONF), "routes.conf was not created"
    with open(ROUTES_CONF, "r") as f:
        content = f.read().strip()
    assert content == LOW_ROUTE, "routes.conf content is incorrect for <= 50MB"

    log_lines = get_log_lines()
    assert len(log_lines) == 1, "Expected exactly 1 log line after first run"
    assert re.search(r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ROUTE_CHANGED: 192\.168\.1\.1", log_lines[0]), "Log format incorrect for <= 50MB"

    subprocess.run([script_path], check=True)
    assert len(get_log_lines()) == 1, "Script is not idempotent; it appended to the log when state didn't change"

    create_dummy_file(45, "test2.dat")
    subprocess.run([script_path], check=True)

    with open(ROUTES_CONF, "r") as f:
        content = f.read().strip()
    assert content == HIGH_ROUTE, "routes.conf content is incorrect for > 50MB"

    log_lines = get_log_lines()
    assert len(log_lines) == 2, "Expected exactly 2 log lines after second state change"
    assert re.search(r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ROUTE_CHANGED: 192\.168\.2\.254", log_lines[1]), "Log format incorrect for > 50MB"

    subprocess.run([script_path], check=True)
    assert len(get_log_lines()) == 2, "Script is not idempotent; it appended to the log when state didn't change"


def randomized_sizes(total):
    mib = 1024 * 1024
    for _ in range(10000):
        parts = [4 * mib + secrets.randbelow(5 * mib + 1) for _ in range(7)]
        final = total - sum(parts)
        if 4 * mib <= final <= 10 * mib:
            parts.append(final)
            # Fisher-Yates shuffle using runtime randomness.
            for i in range(len(parts) - 1, 0, -1):
                j = secrets.randbelow(i + 1)
                parts[i], parts[j] = parts[j], parts[i]
            return parts
    raise AssertionError("Could not construct randomized test contents")


def test_randomized_arbitrary_directory_contents():
    script_path = get_script_path()
    if not script_path:
        pytest.fail("Script not found")

    # The state order, exact byte totals, names, and layout are selected only at
    # verification time, preventing solutions keyed to the original fixtures.
    states = [False, False, True, True]
    for i in range(len(states) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        states[i], states[j] = states[j], states[i]

    mib = 1024 * 1024
    for is_high in states:
        clear_data_volume()
        reset_outputs()

        if is_high:
            total = THRESHOLD + 512 * 1024 + secrets.randbelow(6 * mib)
            expected_route = HIGH_ROUTE
            expected_gateway = "192.168.2.254"
        else:
            total = THRESHOLD - 512 * 1024 - secrets.randbelow(5 * mib)
            expected_route = LOW_ROUTE
            expected_gateway = "192.168.1.1"

        token = secrets.token_hex(8)
        sizes = randomized_sizes(total)
        for index, size in enumerate(sizes):
            if index % 3 == 0:
                relative = os.path.join(f"dir_{token}_{index}", f"blob_{secrets.token_hex(5)}.bin")
            elif index % 3 == 1:
                relative = os.path.join(f"dir_{token}_{index}", "nested", f"item_{secrets.token_hex(5)}")
            else:
                relative = f"payload_{secrets.token_hex(6)}_{index}.dat"
            write_sized_file(os.path.join(DATA_VOLUME, relative), size)

        assert sum(
            os.path.getsize(os.path.join(root, name))
            for root, _, files in os.walk(DATA_VOLUME)
            for name in files
        ) == total

        subprocess.run([script_path], check=True)
        assert_route_and_log(expected_route, expected_gateway, 1)

        subprocess.run([script_path], check=True)
        assert_route_and_log(expected_route, expected_gateway, 1)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
