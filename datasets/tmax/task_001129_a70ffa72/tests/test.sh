#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import json
import random
import subprocess
import uuid
import pytest

BINARY = "/home/user/migrator/target/release/migrator"
DATA_PATH = "/home/user/migration_data/legacy_services.json"
ROUTES_PATH = "/home/user/output/apply_routes.sh"
FSTAB_PATH = "/home/user/output/mock_fstab"


def test_rust_binary_compiled():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Rust release binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Rust binary at {binary_path} is not executable"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not a compiled ELF executable"


def test_apply_routes_script():
    script_path = ROUTES_PATH
    assert os.path.isfile(script_path), f"File {script_path} does not exist"

    # Check if executable
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable"

    with open(script_path, "r") as f:
        content = f.read().strip().split('\n')

    assert len(content) >= 1, f"{script_path} is empty"
    assert content[0] == "#!/bin/bash", f"{script_path} does not start with #!/bin/bash"

    # Check for correct routes
    expected_routes = [
        "ip route add 10.5.1.100/32 via 10.99.0.1",
        "ip route add 10.5.1.102/32 via 10.99.0.1"
    ]

    # Filter out empty lines or just shebang
    actual_routes = [line.strip() for line in content[1:] if line.strip()]

    assert actual_routes == expected_routes, f"Routes in {script_path} do not match expected output. Got: {actual_routes}"


def test_mock_fstab():
    fstab_path = FSTAB_PATH
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist"

    with open(fstab_path, "r") as f:
        content = [line.strip() for line in f.readlines() if line.strip()]

    expected_fstab = [
        "10.10.10.50:/vol/db-main /home/user/mnt/db-main nfs defaults,user,noauto 0 0",
        "10.10.10.51:/vol/assets /home/user/mnt/assets nfs defaults,user,noauto 0 0"
    ]

    assert content == expected_fstab, f"Fstab entries in {fstab_path} do not match expected output. Got: {content}"


def test_crontab_dump():
    dump_path = "/home/user/output/crontab_dump.txt"
    assert os.path.isfile(dump_path), f"File {dump_path} does not exist"

    with open(dump_path, "r") as f:
        content = f.read()

    expected_cron = "*/5 * * * * /home/user/migrator/target/release/migrator"
    assert expected_cron in content, f"Expected cron job '{expected_cron}' not found in {dump_path}"


def test_cron_job_is_actually_installed():
    expected_cron = "*/5 * * * * /home/user/migrator/target/release/migrator"
    result = subprocess.run(
        ["crontab", "-u", "user", "-l"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"Could not read user's installed crontab: {result.stderr}"
    active_lines = [
        line.strip() for line in result.stdout.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    assert active_lines.count(expected_cron) == 1, (
        f"Expected exactly one installed cron job '{expected_cron}', got: {active_lines}"
    )


def run_binary_and_check(services):
    with open(DATA_PATH, "w") as f:
        json.dump(services, f)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", BINARY],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Compiled migrator failed on generated input. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    migrated = [service for service in services if service["status"] == "migrated"]
    expected_routes = ["#!/bin/bash"] + [
        f"ip route add {service['ip_address']}/32 via 10.99.0.1"
        for service in migrated
    ]
    expected_fstab = [
        f"{service['nfs_export']} /home/user/mnt/{service['service_name']} nfs defaults,user,noauto 0 0"
        for service in migrated
    ]

    assert os.path.isfile(ROUTES_PATH), f"Binary did not create {ROUTES_PATH}"
    assert os.path.isfile(FSTAB_PATH), f"Binary did not create {FSTAB_PATH}"
    assert os.stat(ROUTES_PATH).st_mode & stat.S_IXUSR, f"{ROUTES_PATH} is not executable"

    with open(ROUTES_PATH) as f:
        actual_routes = [line.strip() for line in f.read().splitlines() if line.strip()]
    with open(FSTAB_PATH) as f:
        actual_fstab = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert actual_routes == expected_routes, (
        f"Routes generated from changed input are incorrect. Got {actual_routes}, expected {expected_routes}"
    )
    assert actual_fstab == expected_fstab, (
        f"Fstab generated from changed input is incorrect. Got {actual_fstab}, expected {expected_fstab}"
    )


def test_binary_processes_changed_input_and_overwrites_outputs():
    token = uuid.uuid4().hex[:10]
    octet = random.SystemRandom().randint(20, 220)

    first_services = [
        {
            "service_name": f"dynamic-{token}-a",
            "ip_address": f"172.23.{octet}.11",
            "status": "migrated",
            "nfs_export": f"192.0.2.{octet}:/exports/{token}-a",
        },
        {
            "service_name": f"dynamic-{token}-pending",
            "ip_address": f"172.23.{octet}.12",
            "status": "pending",
            "nfs_export": f"192.0.2.{octet}:/exports/{token}-pending",
        },
        {
            "service_name": f"dynamic-{token}-b",
            "ip_address": f"172.23.{octet}.13",
            "status": "migrated",
            "nfs_export": f"192.0.2.{octet}:/exports/{token}-b",
        },
    ]

    for path in (ROUTES_PATH, FSTAB_PATH):
        if os.path.exists(path):
            os.remove(path)
    run_binary_and_check(first_services)

    # Run again without deleting outputs to verify that stale data is overwritten.
    second_services = [
        {
            "service_name": f"replacement-{token}",
            "ip_address": f"198.51.100.{random.SystemRandom().randint(10, 240)}",
            "status": "migrated",
            "nfs_export": f"203.0.113.{octet}:/new/{token}",
        },
        {
            "service_name": f"case-{token}",
            "ip_address": f"198.51.100.{random.SystemRandom().randint(10, 240)}",
            "status": "Migrated",
            "nfs_export": f"203.0.113.{octet}:/ignored/{token}",
        },
    ]
    run_binary_and_check(second_services)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
