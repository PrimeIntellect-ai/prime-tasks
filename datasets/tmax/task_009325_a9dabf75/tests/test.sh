#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/build_restore.sh"
CSV_PATH = "/home/user/backup_metadata.csv"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_restore_plan_1():
    plan_path = "/home/user/restore_plan_1.json"
    assert os.path.isfile(plan_path), f"File {plan_path} is missing."

    with open(plan_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {plan_path} does not contain valid JSON."

    assert data.get("target") == "bkp_007", f"Incorrect target in {plan_path}."
    assert data.get("valid") is True, f"Expected valid=true in {plan_path}."
    assert data.get("chain") == ["bkp_001", "bkp_003", "bkp_005", "bkp_006", "bkp_007"], f"Incorrect chain in {plan_path}."
    assert data.get("total_size_mb") == 5555, f"Incorrect total_size_mb in {plan_path}."


def test_restore_plan_2():
    plan_path = "/home/user/restore_plan_2.json"
    assert os.path.isfile(plan_path), f"File {plan_path} is missing."

    with open(plan_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {plan_path} does not contain valid JSON."

    assert data.get("target") == "bkp_009", f"Incorrect target in {plan_path}."
    assert data.get("valid") is False, f"Expected valid=false in {plan_path}."
    assert "chain" not in data, f"chain should not be present in invalid plan {plan_path}."
    assert "total_size_mb" not in data, f"total_size_mb should not be present in invalid plan {plan_path}."


def test_script_dynamic_behavior():
    # Test valid target
    result = subprocess.run([SCRIPT_PATH, "bkp_002"], capture_output=True, text=True)
    assert result.returncode == 0, "Script failed when running dynamically for bkp_002."

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, "Script output for bkp_002 is not valid JSON."

    assert data.get("target") == "bkp_002"
    assert data.get("valid") is True
    assert data.get("chain") == ["bkp_001", "bkp_002"]
    assert data.get("total_size_mb") == 5250

    # Test invalid target
    result = subprocess.run([SCRIPT_PATH, "bkp_004"], capture_output=True, text=True)
    assert result.returncode == 0, "Script failed when running dynamically for bkp_004."

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        assert False, "Script output for bkp_004 is not valid JSON."

    assert data.get("target") == "bkp_004"
    assert data.get("valid") is False


def test_script_uses_catalog_and_handles_arbitrary_lineages():
    original_bytes = open(CSV_PATH, "rb").read()
    original_mode = stat.S_IMODE(os.stat(CSV_PATH).st_mode)

    numbers = random.sample(range(100000, 999999), 9)
    ids = [f"bkp_{number}" for number in numbers]
    missing_parent = f"bkp_{random.randrange(1000000, 9999999)}"
    while missing_parent in ids:
        missing_parent = f"bkp_{random.randrange(1000000, 9999999)}"

    sizes = [random.randrange(11, 9000) for _ in ids]
    rows = [
        (ids[0], "NONE", sizes[0], "SUCCESS"),
        (ids[1], ids[0], sizes[1], "SUCCESS"),
        (ids[2], ids[1], sizes[2], "SUCCESS"),
        (ids[3], ids[0], sizes[3], "FAILED"),
        (ids[4], ids[3], sizes[4], "SUCCESS"),
        (ids[5], ids[2], sizes[5], "FAILED"),
        (ids[6], missing_parent, sizes[6], "SUCCESS"),
        (ids[7], "NONE", sizes[7], "SUCCESS"),
        (ids[8], ids[7], sizes[8], "SUCCESS"),
    ]
    random.shuffle(rows)

    catalog = "backup_id,parent_backup_id,size_mb,status\n" + "".join(
        f"{backup_id},{parent},{size},{status_value}\n"
        for backup_id, parent, size, status_value in rows
    )
    by_id = {
        backup_id: (parent, size, status_value)
        for backup_id, parent, size, status_value in rows
    }

    def expected_for(target):
        current = target
        seen = set()
        reverse_chain = []
        total = 0
        while True:
            if current in seen or current not in by_id:
                return {"target": target, "valid": False}
            seen.add(current)
            parent, size, status_value = by_id[current]
            if status_value != "SUCCESS":
                return {"target": target, "valid": False}
            reverse_chain.append(current)
            total += size
            if parent == "NONE":
                return {
                    "target": target,
                    "valid": True,
                    "chain": list(reversed(reverse_chain)),
                    "total_size_mb": total,
                }
            current = parent

    def install_catalog(content, mode=0o666):
        fd, temporary_path = tempfile.mkstemp(dir="/home/user")
        try:
            with os.fdopen(fd, "wb") as temporary_file:
                if isinstance(content, str):
                    content = content.encode()
                temporary_file.write(content)
            os.chmod(temporary_path, mode)
            os.replace(temporary_path, CSV_PATH)
        finally:
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)

    try:
        # Reinstall the same generated catalog before every invocation so each
        # answer must be based on the supplied metadata rather than fixed IDs.
        for target in ids:
            install_catalog(catalog)
            result = subprocess.run(
                [SCRIPT_PATH, target], capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0, f"Script failed for generated target {target}."
            try:
                actual = json.loads(result.stdout)
            except json.JSONDecodeError:
                assert False, f"Script output for generated target {target} is not valid JSON."
            assert actual == expected_for(target), (
                f"Incorrect result for generated target {target}: "
                f"expected {expected_for(target)!r}, got {actual!r}"
            )
    finally:
        install_catalog(original_bytes, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
