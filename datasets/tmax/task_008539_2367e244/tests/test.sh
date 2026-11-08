#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import heapq
import os
import secrets
import shutil
import stat
import subprocess
import tempfile


def run_script():
    return subprocess.run(
        ["/home/user/resolve_build.sh"],
        capture_output=True,
        text=True,
        timeout=10,
    )


def read_plan():
    with open("/home/user/build_plan.txt", "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_script_exists_and_executable():
    script_path = "/home/user/resolve_build.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_build_plan_correct():
    plan_path = "/home/user/build_plan.txt"
    assert os.path.isfile(plan_path), f"Build plan {plan_path} does not exist."

    lines = read_plan()
    expected_order = [
        "base.tar",
        "crypto.so",
        "net.so",
        "backend.bin",
        "frontend.bin",
        "release.zip",
    ]

    assert lines == expected_order, f"Build plan order is incorrect. Expected {expected_order}, got {lines}."


def test_script_executes_successfully_on_original_graph():
    expected_order = [
        "base.tar",
        "crypto.so",
        "net.so",
        "backend.bin",
        "frontend.bin",
        "release.zip",
    ]
    result = run_script()
    assert result.returncode == 0, f"Script failed on the valid original graph: {result.stdout}{result.stderr}"
    assert read_plan() == expected_order


def test_script_behavior_on_checksum_failure():
    script_path = "/home/user/resolve_build.sh"
    artifact_path = "/home/user/artifacts/backend.bin"

    assert os.path.isfile(artifact_path), f"Artifact {artifact_path} is missing."

    with open(artifact_path, "rb") as f:
        original_content = f.read()

    try:
        with open(artifact_path, "wb") as f:
            f.write(b"corrupted_content_for_test")

        result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)

        assert result.returncode == 1, f"Expected script to exit with status 1 on checksum failure, but got {result.returncode}."
        assert "ERROR: backend.bin" in result.stdout, f"Expected 'ERROR: backend.bin' in stdout, but got: {result.stdout}"
    finally:
        with open(artifact_path, "wb") as f:
            f.write(original_content)


def derive_order(names, dependencies):
    remaining = {name: set(dependencies[name]) for name in names}
    ready = [name for name in names if not remaining[name]]
    heapq.heapify(ready)
    order = []

    while ready:
        current = heapq.heappop(ready)
        order.append(current)
        for name in names:
            if current in remaining[name]:
                remaining[name].remove(current)
                if not remaining[name] and name not in order and name not in ready:
                    heapq.heappush(ready, name)

    assert len(order) == len(names)
    return order


def test_generated_graph_toposort_and_integrity_checks():
    graph_path = "/home/user/ci_deps.graph"
    artifacts_path = "/home/user/artifacts"
    plan_path = "/home/user/build_plan.txt"

    with tempfile.TemporaryDirectory() as backup_root:
        backup_artifacts = os.path.join(backup_root, "artifacts")
        shutil.copytree(artifacts_path, backup_artifacts)
        with open(graph_path, "rb") as f:
            original_graph = f.read()
        plan_existed = os.path.isfile(plan_path)
        original_plan = None
        if plan_existed:
            with open(plan_path, "rb") as f:
                original_plan = f.read()

        try:
            shutil.rmtree(artifacts_path)
            os.makedirs(artifacts_path)

            roles = ["root1", "root2", "left", "right", "merge", "final"]
            names = {role: f"{secrets.token_hex(6)}_{role}.bin" for role in roles}
            dependencies_by_role = {
                "root1": [],
                "root2": [],
                "left": ["root1"],
                "right": ["root1"],
                "merge": ["root2", "left"],
                "final": ["right", "merge"],
            }
            dependencies = {
                names[role]: [names[dep] for dep in dependencies_by_role[role]]
                for role in roles
            }

            hashes = {}
            for role in roles:
                name = names[role]
                content = secrets.token_bytes(31) + role.encode("ascii") + b"\n"
                with open(os.path.join(artifacts_path, name), "wb") as f:
                    f.write(content)
                hashes[name] = hashlib.sha256(content).hexdigest()

            graph_roles = roles[:]
            secrets.SystemRandom().shuffle(graph_roles)
            with open(graph_path, "w") as f:
                for role in graph_roles:
                    name = names[role]
                    dep_field = ",".join(dependencies[name])
                    f.write(f"{name} : {hashes[name]} : {dep_field}\n")

            expected = derive_order(list(names.values()), dependencies)
            result = run_script()
            assert result.returncode == 0, f"Script failed on generated valid graph: {result.stdout}{result.stderr}"
            assert os.path.isfile(plan_path), "Script did not create build_plan.txt"
            assert read_plan() == expected, f"Generated graph order is incorrect. Expected {expected}, got {read_plan()}"

            corrupt_name = names["right"]
            corrupt_path = os.path.join(artifacts_path, corrupt_name)
            with open(corrupt_path, "ab") as f:
                f.write(b"corruption")
            result = run_script()
            assert result.returncode == 1, f"Expected status 1 for generated checksum failure, got {result.returncode}"
            assert f"ERROR: {corrupt_name}" in result.stdout, f"Expected error for {corrupt_name}, got: {result.stdout}"

            with open(corrupt_path, "wb") as f:
                content = None
            # Recreate the valid content using a fresh graph checksum before testing a missing file.
            replacement = secrets.token_bytes(19) + b"replacement\n"
            with open(corrupt_path, "wb") as f:
                f.write(replacement)
            hashes[corrupt_name] = hashlib.sha256(replacement).hexdigest()
            with open(graph_path, "w") as f:
                for role in graph_roles:
                    name = names[role]
                    dep_field = ",".join(dependencies[name])
                    f.write(f"{name} : {hashes[name]} : {dep_field}\n")

            missing_name = names["root2"]
            os.remove(os.path.join(artifacts_path, missing_name))
            result = run_script()
            assert result.returncode == 1, f"Expected status 1 for missing generated artifact, got {result.returncode}"
            assert f"ERROR: {missing_name}" in result.stdout, f"Expected error for {missing_name}, got: {result.stdout}"
        finally:
            if os.path.exists(artifacts_path):
                shutil.rmtree(artifacts_path)
            shutil.copytree(backup_artifacts, artifacts_path)
            with open(graph_path, "wb") as f:
                f.write(original_graph)
            if plan_existed:
                with open(plan_path, "wb") as f:
                    f.write(original_plan)
            elif os.path.exists(plan_path):
                os.remove(plan_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
