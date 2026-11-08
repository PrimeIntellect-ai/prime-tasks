#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import time
import subprocess
import pytest


def wait_for_processing(incoming_path, processed_path):
    for _ in range(50):
        if os.path.exists(processed_path) and not os.path.exists(incoming_path):
            return
        time.sleep(0.1)


def test_directories_exist():
    """Verify that the required directories have been created."""
    assert os.path.isdir("/home/user/wal_incoming"), "/home/user/wal_incoming directory is missing"
    assert os.path.isdir("/home/user/wal_processed"), "/home/user/wal_processed directory is missing"
    assert os.path.isdir("/home/user/config_active"), "/home/user/config_active directory is missing"


def test_script_exists_and_executable():
    """Verify that the watcher script exists and is executable."""
    script_path = "/home/user/config_watcher.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"


def test_watcher_running():
    """Verify that the watcher script is running in the background."""
    output = subprocess.check_output(["ps", "-ef"]).decode()
    assert "config_watcher.sh" in output, "config_watcher.sh is not running in the background"


def test_processing_wal_file():
    """Simulate dropping a WAL file and verify correct processing."""
    wal_content = """# BEGIN TEST FILE
TXN:1001|SYS:network|CMD:set ip 192.168.1.50
TXN:1002|SYS:auth|CMD:add_user admin
# This is a comment
TXN:1003|SYS:network|CMD:restart_interface eth0
TXN:1004|SYS:storage|CMD:mount /dev/sdb1 /mnt/data
# END TEST FILE
"""
    incoming_path = "/home/user/wal_incoming/verify.wal"
    processed_path = "/home/user/wal_processed/verify.wal"

    with open(incoming_path, "w") as f:
        f.write(wal_content)

    for _ in range(50):
        if os.path.exists(processed_path):
            break
        time.sleep(0.1)

    assert os.path.exists(processed_path), "verify.wal was not moved to wal_processed within 5 seconds. Is the polling loop working?"
    assert not os.path.exists(incoming_path), "verify.wal was not removed from wal_incoming."

    network_conf = "/home/user/config_active/network.conf"
    auth_conf = "/home/user/config_active/auth.conf"
    storage_conf = "/home/user/config_active/storage.conf"

    assert os.path.exists(network_conf), "network.conf was not created in config_active"
    with open(network_conf, "r") as f:
        content = f.read().strip()
        expected = "set ip 192.168.1.50\nrestart_interface eth0"
        assert content == expected, f"network.conf contents incorrect.\nExpected:\n{expected}\nGot:\n{content}"

    assert os.path.exists(auth_conf), "auth.conf was not created in config_active"
    with open(auth_conf, "r") as f:
        content = f.read().strip()
        expected = "add_user admin"
        assert content == expected, f"auth.conf contents incorrect.\nExpected:\n{expected}\nGot:\n{content}"

    assert os.path.exists(storage_conf), "storage.conf was not created in config_active"
    with open(storage_conf, "r") as f:
        content = f.read().strip()
        expected = "mount /dev/sdb1 /mnt/data"
        assert content == expected, f"storage.conf contents incorrect.\nExpected:\n{expected}\nGot:\n{content}"


def test_randomized_wal_parsing_distribution_and_append():
    """Exercise arbitrary WAL names, values, invalid lines, distribution, and appending."""
    token = secrets.token_hex(10)
    subsystem_a = f"svc_{token}_a"
    subsystem_b = f"svc_{token}_b"
    invalid_subsystem = f"ignored_{token}"
    command_a1 = f"set generated value {secrets.token_hex(12)}"
    command_a2 = f"reload generated-{secrets.token_hex(8)}"
    command_b1 = f"enable feature {secrets.token_hex(9)}"
    command_a3 = f"append check {secrets.token_hex(11)}"

    conf_a = f"/home/user/config_active/{subsystem_a}.conf"
    conf_b = f"/home/user/config_active/{subsystem_b}.conf"
    invalid_conf = f"/home/user/config_active/{invalid_subsystem}.conf"
    assert not os.path.exists(conf_a)
    assert not os.path.exists(conf_b)
    assert not os.path.exists(invalid_conf)

    first_name = f"generated_{secrets.token_hex(8)}.wal"
    first_incoming = f"/home/user/wal_incoming/{first_name}"
    first_processed = f"/home/user/wal_processed/{first_name}"
    txn = secrets.randbelow(900000000) + 100000000
    first_content = (
        f"# randomized verifier payload {token}\n"
        f"TXN:{txn}|SYS:{subsystem_a}|CMD:{command_a1}\n"
        f"TXN:{txn + 1}|SYS:{invalid_subsystem}|BAD:not a command\n"
        "this is not a WAL record\n"
        f"TXN:{txn + 2}|SYS:{subsystem_b}|CMD:{command_b1}\n"
        f"# TXN:{txn + 3}|SYS:{invalid_subsystem}|CMD:commented out\n"
        "\n"
        f"TXN:{txn + 4}|SYS:{subsystem_a}|CMD:{command_a2}\n"
    )
    with open(first_incoming, "w") as f:
        f.write(first_content)

    wait_for_processing(first_incoming, first_processed)
    assert os.path.exists(first_processed), f"{first_name} was not moved to wal_processed within 5 seconds"
    assert not os.path.exists(first_incoming), f"{first_name} remains in wal_incoming"
    assert os.path.isfile(conf_a), f"{subsystem_a}.conf was not created"
    assert os.path.isfile(conf_b), f"{subsystem_b}.conf was not created"
    with open(conf_a, "rb") as f:
        assert f.read() == (command_a1 + "\n" + command_a2 + "\n").encode()
    with open(conf_b, "rb") as f:
        assert f.read() == (command_b1 + "\n").encode()
    assert not os.path.exists(invalid_conf), "A malformed or commented WAL line was processed"

    second_name = f"generated_{secrets.token_hex(8)}.wal"
    second_incoming = f"/home/user/wal_incoming/{second_name}"
    second_processed = f"/home/user/wal_processed/{second_name}"
    with open(second_incoming, "w") as f:
        f.write(f"TXN:{txn + 5}|SYS:{subsystem_a}|CMD:{command_a3}\n")

    wait_for_processing(second_incoming, second_processed)
    assert os.path.exists(second_processed), f"{second_name} was not moved to wal_processed within 5 seconds"
    assert not os.path.exists(second_incoming), f"{second_name} remains in wal_incoming"
    with open(conf_a, "rb") as f:
        expected = (command_a1 + "\n" + command_a2 + "\n" + command_a3 + "\n").encode()
        assert f.read() == expected, "Commands from a later WAL were not appended correctly"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
