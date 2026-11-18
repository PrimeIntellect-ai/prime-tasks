#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid
from pathlib import Path

import pytest


def test_bare_repo_exists():
    """Ensure the bare Git repository was created."""
    bare_repo_path = "/home/user/git-server/deploy.git"
    assert os.path.isdir(bare_repo_path), f"Bare Git repository not found at {bare_repo_path}"
    assert os.path.isdir(os.path.join(bare_repo_path, "objects")), f"Directory {bare_repo_path} does not appear to be a bare git repository."

    result = subprocess.run(
        ["git", "--git-dir", bare_repo_path, "rev-parse", "--is-bare-repository"],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Git cannot open the bare repository: {result.stderr}"
    assert result.stdout.strip() == "true", f"Repository at {bare_repo_path} is not bare."


def test_deploy_directories_exist():
    """Ensure the deployment directories exist."""
    src_dir = "/home/user/deploy/src"
    out_dir = "/home/user/deploy/out"
    assert os.path.isdir(src_dir), f"Deployment source directory not found at {src_dir}"
    assert os.path.isdir(out_dir), f"Deployment output directory not found at {out_dir}"


def test_post_receive_hook_exists_and_executable():
    """Ensure the post-receive hook exists and is executable."""
    hook_path = "/home/user/git-server/deploy.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"post-receive hook not found at {hook_path}"
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"post-receive hook at {hook_path} is not executable."


def test_workspace_exists():
    """Ensure the workspace directory exists and has the required files."""
    workspace_dir = "/home/user/workspace"
    assert os.path.isdir(workspace_dir), f"Workspace directory not found at {workspace_dir}"
    assert os.path.isdir(os.path.join(workspace_dir, ".git")), f"Workspace at {workspace_dir} is not a git repository."

    fstab_path = os.path.join(workspace_dir, "virtual_fstab")
    network_path = os.path.join(workspace_dir, "network_links.txt")
    assert os.path.isfile(fstab_path), f"File {fstab_path} not found in workspace."
    assert os.path.isfile(network_path), f"File {network_path} not found in workspace."


def test_xfs_volumes_output():
    """Ensure the xfs_volumes.txt file is correctly generated."""
    xfs_file = "/home/user/deploy/out/xfs_volumes.txt"
    assert os.path.isfile(xfs_file), f"Output file not found at {xfs_file}"

    with open(xfs_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = [
        "/app/cache",
        "/app/logs",
        "/opt/db"
    ]

    assert lines == expected, f"Contents of {xfs_file} do not match the expected sorted xfs mount points. Got: {lines}"


def test_mesh_json_output():
    """Ensure the mesh.json file is correctly generated."""
    json_file = "/home/user/deploy/out/mesh.json"
    assert os.path.isfile(json_file), f"Output file not found at {json_file}"

    with open(json_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_file} does not contain valid JSON.")

    expected = {
        "api-gateway": [
            "user-service:8080",
            "payment-service:8443"
        ],
        "user-service": [
            "postgres-db:5432"
        ],
        "payment-service": [
            "postgres-db:5432"
        ]
    }

    for k in data:
        if isinstance(data[k], list):
            data[k].sort()

    for k in expected:
        expected[k].sort()

    assert data == expected, f"Contents of {json_file} do not match the expected mesh dictionary. Got: {data}"


def test_hook_processes_a_new_dynamic_push(tmp_path):
    """Push a fresh commit and verify that the hook dynamically parses it."""
    bare_repo = "/home/user/git-server/deploy.git"
    clone_dir = tmp_path / "dynamic-clone"

    git_config = tmp_path / "gitconfig"
    git_config.write_text("[safe]\n\tdirectory = *\n", encoding="utf-8")
    env = os.environ.copy()
    env["GIT_CONFIG_GLOBAL"] = str(git_config)
    env["GIT_CONFIG_SYSTEM"] = "/dev/null"

    def run(command, cwd=None):
        result = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Command failed: {' '.join(map(str, command))}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        return result.stdout.strip()

    run(["git", "clone", "--branch", "master", bare_repo, str(clone_dir)])
    run(["git", "config", "user.name", "Verifier"], cwd=clone_dir)
    run(["git", "config", "user.email", "verifier@example.invalid"], cwd=clone_dir)

    token = "v" + uuid.uuid4().hex
    xfs_mounts = [
        f"/dynamic/{token}/zeta",
        f"/dynamic/{token}/alpha",
        f"/dynamic/{token}/middle",
    ]
    fstab_text = (
        f"/dev/{token}a {xfs_mounts[0]} xfs defaults 0 0\n"
        f"/dev/{token}b /dynamic/{token}/ignored ext4 defaults 0 0\n"
        f"/dev/{token}c {xfs_mounts[1]} xfs noatime 0 0\n"
        f"server:/share /dynamic/{token}/nfs nfs rw 0 0\n"
        f"/dev/{token}d /dynamic/{token}/not-strict xfs_extra defaults 0 0\n"
        f"/dev/{token}e {xfs_mounts[2]} xfs rw,noexec 0 0\n"
    )

    source_a = f"source-{token}"
    source_b = f"worker-{token}"
    target_a = f"target-{token}"
    target_b = f"database-{token}"
    network_text = (
        f"{source_a} {target_a} 19001\n"
        f"{source_a} {target_b} 19002\n"
        f"{source_b} {target_b} 19003\n"
    )
    marker_text = f"deployment marker {token}\n"

    (clone_dir / "virtual_fstab").write_text(fstab_text, encoding="utf-8")
    (clone_dir / "network_links.txt").write_text(network_text, encoding="utf-8")
    (clone_dir / "deployment_marker.txt").write_text(marker_text, encoding="utf-8")

    run(["git", "add", "virtual_fstab", "network_links.txt", "deployment_marker.txt"], cwd=clone_dir)
    run(["git", "commit", "-m", f"dynamic verifier fixture {token}"], cwd=clone_dir)
    pushed_commit = run(["git", "rev-parse", "HEAD"], cwd=clone_dir)
    run(["git", "push", "origin", "HEAD:master"], cwd=clone_dir)

    deployed_commit = run(["git", "--git-dir", bare_repo, "rev-parse", "refs/heads/master"])
    assert deployed_commit == pushed_commit, "The new commit was not installed on the bare repository's master branch."

    src = Path("/home/user/deploy/src")
    assert (src / "virtual_fstab").read_text(encoding="utf-8") == fstab_text
    assert (src / "network_links.txt").read_text(encoding="utf-8") == network_text
    assert (src / "deployment_marker.txt").read_text(encoding="utf-8") == marker_text, (
        "The hook did not check out all files from the latest pushed commit."
    )

    xfs_path = Path("/home/user/deploy/out/xfs_volumes.txt")
    assert xfs_path.is_file(), "The dynamic push did not generate xfs_volumes.txt."
    actual_mounts = [line.strip() for line in xfs_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert actual_mounts == sorted(xfs_mounts), (
        f"Dynamic xfs parsing was incorrect: expected {sorted(xfs_mounts)}, got {actual_mounts}"
    )

    mesh_path = Path("/home/user/deploy/out/mesh.json")
    assert mesh_path.is_file(), "The dynamic push did not generate mesh.json."
    try:
        actual_mesh = json.loads(mesh_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"Dynamic mesh output is not strict JSON: {exc}")

    expected_mesh = {
        source_a: [f"{target_a}:19001", f"{target_b}:19002"],
        source_b: [f"{target_b}:19003"],
    }
    assert isinstance(actual_mesh, dict)
    for value in actual_mesh.values():
        assert isinstance(value, list) and all(isinstance(item, str) for item in value)
    normalized_mesh = {key: sorted(value) for key, value in actual_mesh.items()}
    normalized_expected = {key: sorted(value) for key, value in expected_mesh.items()}
    assert normalized_mesh == normalized_expected, (
        f"Dynamic network parsing was incorrect: expected {normalized_expected}, got {normalized_mesh}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
