#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import subprocess
import tempfile
import uuid


def test_phase1_active_capacity():
    cap_file = "/home/user/active_capacity.txt"
    assert os.path.isfile(cap_file), f"File {cap_file} is missing. Phase 1 incomplete."

    with open(cap_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected 2 lines in {cap_file}, found {len(lines)}"

    expected_cpu = "ACTIVE_CPU: 30"
    expected_ram = "ACTIVE_RAM: 61440"

    assert expected_cpu in lines, f"Missing or incorrect CPU total. Expected '{expected_cpu}'"
    assert expected_ram in lines, f"Missing or incorrect RAM total. Expected '{expected_ram}'"


def test_phase2_git_hook_executable():
    hook_path = "/home/user/infra.git/hooks/pre-receive"
    assert os.path.isfile(hook_path), f"Git hook missing at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"Git hook at {hook_path} is not executable"

    with open(hook_path, "r", encoding="utf-8") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line.startswith("#!") and "python" in first_line.lower(), \
        "The pre-receive hook must use a Python shebang"
    ast.parse(source, filename=hook_path)


def test_phase2_git_hook_enforcement():
    workspace = "/home/user/infra_workspace"
    assert os.path.isdir(workspace), f"Workspace {workspace} missing"

    # Test rejection (CPU > 200)
    # Active CPU is 30, so adding 171 makes it 201 > 200
    reject_vms = [{"name": "huge", "cpu": 171, "ram": 1024, "env": "dev"}]
    vms_file = os.path.join(workspace, "vms.json")

    with open(vms_file, "w") as f:
        json.dump(reject_vms, f)

    subprocess.run(["git", "add", "vms.json"], cwd=workspace, check=True)
    subprocess.run(["git", "commit", "-m", "test reject"], cwd=workspace, check=True)

    push_result = subprocess.run(
        ["git", "push", "origin", "master"],
        cwd=workspace,
        capture_output=True,
        text=True
    )

    assert push_result.returncode != 0, "Git push should have been rejected by the pre-receive hook"
    assert "CAPACITY EXCEEDED" in push_result.stderr, "Hook did not print 'CAPACITY EXCEEDED' to stderr"

    # Reset commit
    subprocess.run(["git", "reset", "--hard", "HEAD~1"], cwd=workspace, check=True)

    # Test acceptance (CPU <= 200)
    # Active CPU is 30, adding 100 makes it 130 <= 200
    accept_vms = [{"name": "ok", "cpu": 100, "ram": 1024, "env": "dev"}]
    with open(vms_file, "w") as f:
        json.dump(accept_vms, f)

    subprocess.run(["git", "add", "vms.json"], cwd=workspace, check=True)
    subprocess.run(["git", "commit", "-m", "test accept"], cwd=workspace, check=True)

    push_result2 = subprocess.run(
        ["git", "push", "origin", "master"],
        cwd=workspace,
        capture_output=True,
        text=True
    )

    assert push_result2.returncode == 0, f"Git push should have been accepted, but failed: {push_result2.stderr}"


def _active_capacity():
    values = {}
    with open("/home/user/active_capacity.txt", encoding="utf-8") as f:
        for line in f:
            key, value = line.strip().split(":", 1)
            values[key] = int(value.strip())
    return values["ACTIVE_CPU"], values["ACTIVE_RAM"]


def _commit_and_push(workspace, vms, ref_name):
    with open(os.path.join(workspace, "vms.json"), "w", encoding="utf-8") as f:
        json.dump(vms, f)
    subprocess.run(["git", "add", "vms.json"], cwd=workspace, check=True)
    subprocess.run(
        ["git", "commit", "--allow-empty", "-m", "dynamic capacity test " + uuid.uuid4().hex],
        cwd=workspace,
        check=True,
        capture_output=True,
        text=True,
    )
    return subprocess.run(
        ["git", "push", "origin", "HEAD:" + ref_name],
        cwd=workspace,
        capture_output=True,
        text=True,
    )


def test_phase2_dynamic_cpu_ram_aggregation_and_refs():
    workspace = "/home/user/infra_workspace"
    active_cpu, active_ram = _active_capacity()
    cpu_room = 200 - active_cpu
    ram_room = 512000 - active_ram
    assert cpu_room >= 2 and ram_room >= 4096

    rng = random.SystemRandom()

    split_cpu = rng.randint(2, cpu_room)
    cpu_parts = [1, split_cpu // 2, split_cpu - 1 - split_cpu // 2]
    split_ram = rng.randint(3000, min(ram_room, 50000))
    ram_parts = [1000, split_ram // 3, split_ram - 1000 - split_ram // 3]
    aggregate_vms = [
        {"name": "agg_" + uuid.uuid4().hex, "cpu": cpu_parts[i], "ram": ram_parts[i], "env": "dev"}
        for i in range(3)
    ]

    random_safe_cpu = rng.randint(1, cpu_room)
    random_safe_ram = rng.randint(1, ram_room)
    random_over_cpu = cpu_room + rng.randint(1, 40)
    random_over_ram = ram_room + rng.randint(1, 50000)

    cases = [
        ([{"name": uuid.uuid4().hex, "cpu": cpu_room, "ram": 1, "env": "dev"}], True),
        ([{"name": uuid.uuid4().hex, "cpu": cpu_room + 1, "ram": 1, "env": "prod"}], False),
        ([{"name": uuid.uuid4().hex, "cpu": 0, "ram": ram_room, "env": "dev"}], True),
        ([{"name": uuid.uuid4().hex, "cpu": 0, "ram": ram_room + 1, "env": "prod"}], False),
        (aggregate_vms, True),
        ([{"name": uuid.uuid4().hex, "cpu": random_safe_cpu, "ram": random_safe_ram, "env": "dev"}], True),
        ([{"name": uuid.uuid4().hex, "cpu": random_over_cpu, "ram": rng.randint(1, 2048), "env": "prod"}], False),
        ([{"name": uuid.uuid4().hex, "cpu": rng.randint(0, cpu_room), "ram": random_over_ram, "env": "dev"}], False),
    ]
    rng.shuffle(cases)

    for index, (vms, should_accept) in enumerate(cases):
        ref_name = "refs/heads/verify_" + uuid.uuid4().hex
        result = _commit_and_push(workspace, vms, ref_name)
        if should_accept:
            assert result.returncode == 0, \
                f"Valid dynamic push {index} to {ref_name} was rejected: {result.stderr}"
        else:
            assert result.returncode != 0, \
                f"Over-capacity dynamic push {index} to {ref_name} was accepted"
            assert "CAPACITY EXCEEDED" in result.stderr, \
                f"Rejected dynamic push {index} did not report CAPACITY EXCEEDED"

    # Exercise an update to an existing arbitrary ref, so old_value is non-zero.
    update_ref = "refs/heads/update_" + uuid.uuid4().hex
    accepted = _commit_and_push(
        workspace,
        [{"name": uuid.uuid4().hex, "cpu": 1, "ram": 1, "env": "dev"}],
        update_ref,
    )
    assert accepted.returncode == 0, f"Initial arbitrary-ref push failed: {accepted.stderr}"

    rejected_update = _commit_and_push(
        workspace,
        [
            {"name": uuid.uuid4().hex, "cpu": cpu_room // 2 + 1, "ram": 1024, "env": "dev"},
            {"name": uuid.uuid4().hex, "cpu": cpu_room - cpu_room // 2, "ram": 1024, "env": "prod"},
        ],
        update_ref,
    )
    assert rejected_update.returncode != 0, "Over-capacity update of an existing ref was accepted"
    assert "CAPACITY EXCEEDED" in rejected_update.stderr


def test_phase3_roll_deploy():
    script_path = "/home/user/roll_deploy.py"
    assert os.path.isfile(script_path), f"Deployment script missing at {script_path}"

    test_vms = [
        {"name": "test1", "cpu": 2, "ram": 1024, "env": "dev"},
        {"name": "test2", "cpu": 4, "ram": 2048, "env": "prod"}
    ]

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as tmp:
        json.dump(test_vms, tmp)
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            ["python3", script_path, tmp_path],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"roll_deploy.py failed with error: {result.stderr}"

        stage1_conf = "/home/user/deployments/stage_1/test1.conf"
        stage2_conf = "/home/user/deployments/stage_2/test2.conf"

        assert os.path.isfile(stage1_conf), f"Missing {stage1_conf}"
        assert os.path.isfile(stage2_conf), f"Missing {stage2_conf}"

        with open(stage1_conf, "r") as f:
            assert f.read().strip() == "cpu=2,ram=1024", f"Incorrect content in {stage1_conf}"

        with open(stage2_conf, "r") as f:
            assert f.read().strip() == "cpu=4,ram=2048", f"Incorrect content in {stage2_conf}"

    finally:
        os.remove(tmp_path)


def test_phase3_roll_deploy_dynamic_input():
    script_path = "/home/user/roll_deploy.py"
    rng = random.SystemRandom()
    dev_name = "dev_" + uuid.uuid4().hex
    prod_name = "prod_" + uuid.uuid4().hex
    dev_cpu, dev_ram = rng.randint(1, 64), rng.randint(257, 100000)
    prod_cpu, prod_ram = rng.randint(1, 64), rng.randint(257, 100000)
    test_vms = [
        {"name": dev_name, "cpu": dev_cpu, "ram": dev_ram, "env": "dev"},
        {"name": prod_name, "cpu": prod_cpu, "ram": prod_ram, "env": "prod"},
    ]

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as tmp:
        json.dump(test_vms, tmp)
        tmp_path = tmp.name

    try:
        result = subprocess.run(["python3", script_path, tmp_path], capture_output=True, text=True)
        assert result.returncode == 0, f"roll_deploy.py failed on dynamic input: {result.stderr}"

        dev_path = f"/home/user/deployments/stage_1/{dev_name}.conf"
        prod_path = f"/home/user/deployments/stage_2/{prod_name}.conf"
        assert os.path.isdir("/home/user/deployments/stage_1")
        assert os.path.isdir("/home/user/deployments/stage_2")
        assert os.path.isfile(dev_path), f"Missing dynamically named dev file {dev_path}"
        assert os.path.isfile(prod_path), f"Missing dynamically named prod file {prod_path}"
        with open(dev_path, encoding="utf-8") as f:
            assert f.read().strip() == f"cpu={dev_cpu},ram={dev_ram}"
        with open(prod_path, encoding="utf-8") as f:
            assert f.read().strip() == f"cpu={prod_cpu},ram={prod_ram}"
        assert not os.path.exists(f"/home/user/deployments/stage_2/{dev_name}.conf")
        assert not os.path.exists(f"/home/user/deployments/stage_1/{prod_name}.conf")
    finally:
        os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
