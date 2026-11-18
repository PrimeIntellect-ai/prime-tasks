#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import stat
import subprocess
from zoneinfo import ZoneInfo


def get_exported_environment():
    result = subprocess.run(
        [
            "env", "-i", "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "HOME=/home/user", "bash", "--noprofile", "--norc", "-c",
            'unset TZ LC_ALL MAX_DISK_KB; source "$1"; exec env -0',
            "bash", "/home/user/migration_env.sh",
        ],
        capture_output=True,
        check=True,
    )
    entries = result.stdout.split(b"\0")
    return {
        entry.split(b"=", 1)[0].decode(): entry.split(b"=", 1)[1].decode()
        for entry in entries if b"=" in entry
    }


def disk_usage_kb():
    result = subprocess.run(
        ["du", "-sk", "/home/user/migration_data"],
        capture_output=True,
        text=True,
        check=True,
    )
    return int(result.stdout.split()[0])


def expected_timestamp(epoch):
    return datetime.datetime.fromtimestamp(epoch, ZoneInfo("Asia/Tokyo")).strftime("%Y-%m-%d %H:%M:%S")


def run_readiness(epoch, expected_limit):
    usage = disk_usage_kb()
    result = subprocess.run(
        ["/home/user/check_readiness.sh", str(epoch)],
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    expected = f"[{expected_timestamp(epoch)}] INSTANCE:RUNNING DISK_KB:{usage} LIMIT:{expected_limit}"
    assert result.stdout.strip() == expected, (
        f"Script output {result.stdout.strip()!r} did not equal expected output {expected!r}."
    )
    assert len(result.stdout.splitlines()) == 1, "Script must output exactly one log line."
    return result.stdout.strip()


def test_migration_env_file():
    path = "/home/user/migration_env.sh"
    assert os.path.isfile(path), f"File {path} must exist."
    with open(path, "r") as f:
        content = f.read()
    assert "TZ" in content and "Asia/Tokyo" in content, "TZ must be exported as Asia/Tokyo"
    assert "LC_ALL" in content and "C" in content, "LC_ALL must be exported as C"
    assert "MAX_DISK_KB" in content and "10240" in content, "MAX_DISK_KB must be exported as 10240"

    exported = get_exported_environment()
    assert exported.get("TZ") == "Asia/Tokyo", "TZ must actually be exported as Asia/Tokyo"
    assert exported.get("LC_ALL") == "C", "LC_ALL must actually be exported as C"
    assert exported.get("MAX_DISK_KB") == "10240", "MAX_DISK_KB must actually be exported as 10240"


def test_migration_data_payload():
    path = "/home/user/migration_data/payload.bin"
    assert os.path.isfile(path), f"File {path} must exist."
    size = os.path.getsize(path)
    assert size == 12582912, f"File {path} must be exactly 12288 KB (12582912 bytes), but got {size} bytes."

    with open(path, "rb") as payload:
        while True:
            chunk = payload.read(1024 * 1024)
            if not chunk:
                break
            assert not any(chunk), f"File {path} must contain only zero bytes."


def test_apptainer_instance_running():
    result = subprocess.run(["apptainer", "instance", "list"], capture_output=True, text=True)
    assert "service_migrator" in result.stdout, "Apptainer instance 'service_migrator' must be running."


def test_check_readiness_script():
    path = "/home/user/check_readiness.sh"
    assert os.path.isfile(path), f"File {path} must exist."
    st = os.stat(path)
    assert st.st_mode & stat.S_IXUSR, f"File {path} must be executable."

    random_epoch = 946684800 + secrets.randbelow(946684800)
    run_readiness(random_epoch, "EXCEEDED")

    env_path = "/home/user/migration_env.sh"
    with open(env_path, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(env_path).st_mode)
    high_limit = disk_usage_kb() + 100000
    try:
        with open(env_path, "w") as f:
            f.write("export TZ=Asia/Tokyo\n")
            f.write("export LC_ALL=C\n")
            f.write(f"export MAX_DISK_KB={high_limit}\n")
        run_readiness(random_epoch + 12345, "OK")
    finally:
        with open(env_path, "wb") as f:
            f.write(original)
        os.chmod(env_path, original_mode)


def test_final_status_log():
    path = "/home/user/final_status.log"
    assert os.path.isfile(path), f"File {path} must exist."
    with open(path, "r") as f:
        content = f.read().strip()

    pattern = r"^\[2024-03-10 01:00:00\] INSTANCE:RUNNING DISK_KB:\d+ LIMIT:EXCEEDED$"
    assert re.match(pattern, content), f"File {path} content '{content}' does not match expected format."

    match = re.search(r"DISK_KB:(\d+)", content)
    assert match, "DISK_KB value not found in log."
    disk_kb = int(match.group(1))
    assert disk_kb > 10240, f"DISK_KB {disk_kb} should be greater than 10240."

    actual_run = run_readiness(1710000000, "EXCEEDED")
    assert content == actual_run, "final_status.log must equal the actual output of check_readiness.sh."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
