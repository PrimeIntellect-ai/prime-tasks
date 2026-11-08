#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest


def test_git_repo_exists():
    repo_path = "/home/user/manifest-repo.git"
    assert os.path.isdir(repo_path), f"Bare repo directory missing at {repo_path}"
    assert os.path.exists(os.path.join(repo_path, "HEAD")), f"{repo_path} is not a valid bare git repo"


def test_workspace_is_clone():
    workspace = "/home/user/manifest-workspace"
    assert os.path.isdir(workspace), f"Workspace missing at {workspace}"
    result = subprocess.run(
        ["git", "-c", "safe.directory=*", "-C", workspace, "rev-parse", "--is-inside-work-tree"],
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0 and result.stdout.strip() == "true", f"{workspace} is not a Git worktree"
    origin = subprocess.run(
        ["git", "-c", "safe.directory=*", "-C", workspace, "remote", "get-url", "origin"],
        text=True,
        capture_output=True,
    )
    assert origin.returncode == 0, "Workspace has no origin remote"
    assert os.path.realpath(origin.stdout.strip()) == os.path.realpath("/home/user/manifest-repo.git"), \
        "Workspace origin does not point to /home/user/manifest-repo.git"


def test_post_receive_hook_executable():
    hook_path = "/home/user/manifest-repo.git/hooks/post-receive"
    assert os.path.exists(hook_path), f"Hook missing at {hook_path}"
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{hook_path} is not executable"


def test_operator_script_executable():
    script_path = "/home/user/operator.py"
    assert os.path.exists(script_path), f"Operator script missing at {script_path}"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable"


def test_cluster_state_json():
    json_path = "/home/user/cluster_state.json"
    assert os.path.exists(json_path), f"State file missing at {json_path}"

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} does not contain valid JSON")

    assert "backend-api" in data, "Missing 'backend-api' key in cluster_state.json"

    backend_data = data["backend-api"]
    assert backend_data.get("name") == "backend-api", "Incorrect name in JSON"
    assert backend_data.get("image") == "python:3.9-slim", "Incorrect image in JSON"
    assert backend_data.get("replicas") == 2, "Incorrect replicas count in JSON"

    env_data = backend_data.get("env", {})
    assert str(env_data.get("PORT")) == "8080", "Incorrect PORT in JSON env"
    assert env_data.get("DB_HOST") == "pg-cluster.local", "Incorrect DB_HOST in JSON env"


def test_k8s_profile():
    profile_path = "/home/user/.k8s_profile"
    assert os.path.exists(profile_path), f"Profile missing at {profile_path}"

    with open(profile_path, "r") as f:
        content = f.read()

    port_match = re.search(r'export K8S_ENV_BACKEND[-_]API_PORT="?8080"?', content, re.IGNORECASE)
    assert port_match, "PORT export statement missing or malformed in .k8s_profile"

    db_match = re.search(r'export K8S_ENV_BACKEND[-_]API_DB_HOST="?pg-cluster\.local"?', content, re.IGNORECASE)
    assert db_match, "DB_HOST export statement missing or malformed in .k8s_profile"


def test_apply_containers_script():
    script_path = "/home/user/apply_containers.sh"
    assert os.path.exists(script_path), f"Script missing at {script_path}"

    with open(script_path, "r") as f:
        content = f.read()

    assert "set -eo pipefail" in content, "Missing 'set -eo pipefail' in apply_containers.sh"


def test_container_log():
    log_path = "/home/user/container.log"
    assert os.path.exists(log_path), f"Log missing at {log_path} (did the script run?)"

    with open(log_path, "r") as f:
        content = f.read()

    replica_1 = "Starting container python:3.9-slim for deployment backend-api (replica 1)"
    replica_2 = "Starting container python:3.9-slim for deployment backend-api (replica 2)"

    assert replica_1 in content, f"Missing replica 1 start log in {log_path}"
    assert replica_2 in content, f"Missing replica 2 start log in {log_path}"

    # Check that env keys are mentioned
    assert "PORT" in content, "PORT env key missing in log output"
    assert "DB_HOST" in content, "DB_HOST env key missing in log output"


def test_dynamic_push_hook_operator_and_generated_script():
    token = uuid.uuid4().hex[:10]
    name_a = f"verifya{token}"
    name_b = f"verifyb{token}"
    image_a = f"registry.local/service:{token}"
    image_b = f"worker:{token}"
    port = 20000 + (int(token[:4], 16) % 30000)

    expected_state = {
        name_a: {
            "name": name_a,
            "image": image_a,
            "replicas": 1,
            "env": {"TOKEN": token, "PORT": port},
        },
        name_b: {
            "name": name_b,
            "image": image_b,
            "replicas": 3,
            "env": {"MODE": f"mode{token}"},
        },
    }
    expected_profile = {
        f'export K8S_ENV_{name_a.upper()}_TOKEN="{token}"',
        f'export K8S_ENV_{name_a.upper()}_PORT="{port}"',
        f'export K8S_ENV_{name_b.upper()}_MODE="mode{token}"',
    }
    expected_logs = [
        f"Starting container {image_a} for deployment {name_a} (replica 1) with env keys: TOKEN,PORT",
        f"Starting container {image_b} for deployment {name_b} (replica 1) with env keys: MODE",
        f"Starting container {image_b} for deployment {name_b} (replica 2) with env keys: MODE",
        f"Starting container {image_b} for deployment {name_b} (replica 3) with env keys: MODE",
    ]

    subprocess.run(["git", "config", "--global", "--add", "safe.directory", "*"], check=True)

    with tempfile.TemporaryDirectory(prefix="gitops-verifier-") as td:
        clone = Path(td) / "clone"
        subprocess.run(["git", "clone", "/home/user/manifest-repo.git", str(clone)], check=True, capture_output=True, text=True)
        subprocess.run(["git", "-C", str(clone), "config", "user.name", "Verifier"], check=True)
        subprocess.run(["git", "-C", str(clone), "config", "user.email", "verifier@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(clone), "checkout", "-B", "master", "origin/master"], check=True, capture_output=True, text=True)

        for item in clone.iterdir():
            if item.is_file() and item.suffix == ".yaml":
                item.unlink()

        (clone / "dynamic-a.yaml").write_text(
            f"name: {name_a}\n"
            f"image: {image_a}\n"
            "replicas: 1\n"
            "env:\n"
            f"  TOKEN: {token}\n"
            f"  PORT: {port}\n"
        )
        (clone / "dynamic-b.yaml").write_text(
            f"name: {name_b}\n"
            f"image: {image_b}\n"
            "replicas: 3\n"
            "env:\n"
            f"  MODE: mode{token}\n"
        )
        nested = clone / "nested"
        nested.mkdir()
        (nested / "ignored.yaml").write_text(
            "name: must-not-appear\nimage: ignored:latest\nreplicas: 9\nenv:\n  BAD: value\n"
        )

        subprocess.run(["git", "-C", str(clone), "add", "-A"], check=True)
        subprocess.run(["git", "-C", str(clone), "commit", "-m", f"dynamic verifier {token}"], check=True, capture_output=True, text=True)

        Path("/home/user/cluster_state.json").write_text('{"sentinel": true}\n')
        Path("/home/user/.k8s_profile").write_text("PROFILE_SENTINEL\n")
        Path("/home/user/apply_containers.sh").write_text("APPLY_SENTINEL\n")

        push = subprocess.run(
            ["git", "-C", str(clone), "push", "origin", "HEAD:refs/heads/master"],
            text=True,
            capture_output=True,
        )
        assert push.returncode == 0, f"Dynamic push failed:\n{push.stdout}\n{push.stderr}"

    def assert_generated(label):
        with open("/home/user/cluster_state.json") as f:
            actual_state = json.load(f)
        assert actual_state == expected_state, f"{label} did not derive collective state from the new root YAML files"

        profile_lines = {
            line.strip()
            for line in Path("/home/user/.k8s_profile").read_text().splitlines()
            if line.strip()
        }
        assert profile_lines == expected_profile, f"{label} generated an incorrect or non-overwritten .k8s_profile"

        apply_content = Path("/home/user/apply_containers.sh").read_text()
        assert "set -eo pipefail" in apply_content, f"{label} omitted set -eo pipefail"
        assert "APPLY_SENTINEL" not in apply_content, f"{label} did not replace apply_containers.sh"
        for line in expected_logs:
            assert line in apply_content, f"{label} did not generate lifecycle command for: {line}"

    # Sentinels can only be replaced here if the post-receive hook reacts to the push.
    assert_generated("post-receive hook")

    # Independently execute operator.py so the hook cannot substitute for an empty operator.
    Path("/home/user/cluster_state.json").write_text('{"direct_sentinel": true}\n')
    Path("/home/user/.k8s_profile").write_text("DIRECT_PROFILE_SENTINEL\n")
    Path("/home/user/apply_containers.sh").write_text("APPLY_SENTINEL\n")
    direct = subprocess.run(
        ["/home/user/operator.py"],
        cwd="/home/user",
        text=True,
        capture_output=True,
    )
    assert direct.returncode == 0, f"Direct operator execution failed:\n{direct.stdout}\n{direct.stderr}"
    assert_generated("operator.py")

    # Exercise the generated lifecycle script and verify every derived replica line exactly.
    Path("/home/user/container.log").write_text("")
    applied = subprocess.run(
        ["bash", "/home/user/apply_containers.sh"],
        cwd="/home/user",
        text=True,
        capture_output=True,
    )
    assert applied.returncode == 0, f"Generated apply_containers.sh failed:\n{applied.stdout}\n{applied.stderr}"
    actual_logs = [
        line.rstrip("\n")
        for line in Path("/home/user/container.log").read_text().splitlines()
        if line.strip()
    ]
    assert actual_logs == expected_logs, "Generated lifecycle script produced incorrect container log entries"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
