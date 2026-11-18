#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import stat
import subprocess
import tempfile
import time
import uuid


def test_auto_answer_script_exists():
    path = "/home/user/bin/auto_answer.py"
    assert os.path.isfile(path), f"The script {path} does not exist."


def test_post_receive_hook_exists_and_executable():
    path = "/home/user/config_repo.git/hooks/post-receive"
    assert os.path.isfile(path), f"The hook {path} does not exist."
    assert os.access(path, os.X_OK), f"The hook {path} is not executable."


def test_deployment_success_flag():
    path = "/home/user/deployed_services/deploy_success.flag"
    assert os.path.isfile(path), f"The deployment success flag {path} does not exist. The deployment script may not have run correctly or the target directory was incorrect."


def test_hook_metrics_log():
    path = "/home/user/hook_metrics.log"
    assert os.path.isfile(path), f"The metrics log {path} does not exist."

    with open(path, "r") as f:
        content = f.read().splitlines()

    assert "inventory" in content, f"The metrics log {path} does not contain 'inventory'. Found: {content}"


def test_inventory_yml_in_repo():
    repo_path = "/home/user/config_repo.git"
    result = subprocess.run(
        ["git", "ls-tree", "-r", "HEAD"],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, "Failed to run git ls-tree in the bare repository."
    assert "inventory.yml" in result.stdout, "inventory.yml was not found in the HEAD of the bare repository."


def test_auto_answer_uses_pexpect_and_waits_for_the_prompted_process():
    auto_path = "/home/user/bin/auto_answer.py"
    source = open(auto_path, "r").read()
    tree = ast.parse(source, filename=auto_path)

    module_aliases = set()
    spawn_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for name in node.names:
                if name.name == "pexpect":
                    module_aliases.add(name.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for name in node.names:
                if name.name == "spawn":
                    spawn_aliases.add(name.asname or "spawn")

    uses_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            uses_spawn |= (
                node.func.attr == "spawn"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in module_aliases
            )
        elif isinstance(node.func, ast.Name):
            uses_spawn |= node.func.id in spawn_aliases
    assert uses_spawn, "auto_answer.py must use pexpect.spawn."

    deploy_path = "/home/user/bin/deploy_configs.py"
    original = open(deploy_path, "rb").read()
    original_mode = stat.S_IMODE(os.stat(deploy_path).st_mode)
    marker = f"/tmp/auto_answer_probe_{uuid.uuid4().hex}"
    token = uuid.uuid4().hex
    probe = '''#!/usr/bin/env python3
import os
import sys
import time
sys.stdout.write("Apply changes? [y/N]: ")
sys.stdout.flush()
answer = sys.stdin.readline()
if answer != "y\\n":
    sys.exit(23)
time.sleep(0.6)
with open(os.environ["AUTO_PROBE_MARKER"], "w") as f:
    f.write(os.environ["AUTO_PROBE_TOKEN"])
time.sleep(0.3)
'''

    try:
        with open(deploy_path, "w") as f:
            f.write(probe)
        os.chmod(deploy_path, 0o755)
        env = os.environ.copy()
        env["AUTO_PROBE_MARKER"] = marker
        env["AUTO_PROBE_TOKEN"] = token
        started = time.monotonic()
        result = subprocess.run(
            ["/usr/bin/python3", auto_path],
            env=env,
            capture_output=True,
            text=True,
            timeout=8,
        )
        elapsed = time.monotonic() - started
        assert result.returncode == 0, f"auto_answer.py failed against the interactive deployment process: {result.stdout} {result.stderr}"
        assert elapsed >= 0.8, "auto_answer.py returned before the spawned process exited."
        assert os.path.isfile(marker), "The prompted process did not receive 'y' followed by a newline."
        assert open(marker).read() == token
    finally:
        with open(deploy_path, "wb") as f:
            f.write(original)
        os.chmod(deploy_path, original_mode)
        if os.path.exists(marker):
            os.unlink(marker)


def test_hook_configuration_and_fresh_push_behavior():
    hook_path = "/home/user/config_repo.git/hooks/post-receive"
    hook = open(hook_path, "r").read()
    assert re.search(r"export\s+MICRO_DEPLOY_PATH\s*=\s*['\"]?/home/user/deployed_services['\"]?", hook), \
        "The hook must set and export MICRO_DEPLOY_PATH."
    assert re.search(r"/usr/bin/python3\s+['\"]?/home/user/bin/auto_answer\.py['\"]?", hook), \
        "The hook must execute auto_answer.py with /usr/bin/python3."
    assert "git diff-tree" in hook, "The hook must process pushed revisions with git diff-tree."
    assert "|" in hook and re.search(r"\b(grep|awk|sed|basename)\b", hook), \
        "The hook must use a text-processing pipeline for changed YAML paths."

    flag = "/home/user/deployed_services/deploy_success.flag"
    wrong_flag = "/tmp/default_deploy/deploy_success.flag"
    metrics = "/home/user/hook_metrics.log"
    for path in (flag, wrong_flag, metrics):
        if os.path.exists(path):
            os.unlink(path)

    unique = uuid.uuid4().hex
    yaml_base = f"routes_{unique}"
    non_yaml_base = f"ignore_{unique}"

    with tempfile.TemporaryDirectory(prefix="verify_config_push_") as td:
        clone = os.path.join(td, "clone")
        subprocess.run(
            ["git", "clone", "/home/user/config_repo.git", clone],
            check=True,
            capture_output=True,
            text=True,
        )
        os.makedirs(os.path.join(clone, "networking"), exist_ok=True)
        with open(os.path.join(clone, "networking", yaml_base + ".yml"), "w") as f:
            f.write("enabled: true\n")
        with open(os.path.join(clone, "inventory.yml"), "w") as f:
            f.write(f"verification: {unique}\n")
        with open(os.path.join(clone, non_yaml_base + ".txt"), "w") as f:
            f.write("not yaml\n")
        subprocess.run(["git", "add", "."], cwd=clone, check=True)
        subprocess.run(
            ["git", "commit", "-m", f"Verifier push {unique}"],
            cwd=clone,
            check=True,
            capture_output=True,
            text=True,
        )
        pushed = subprocess.run(
            ["git", "push", "origin", "HEAD:master"],
            cwd=clone,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert pushed.returncode == 0, f"Fresh push failed: {pushed.stdout}\n{pushed.stderr}"

    assert os.path.isfile(flag), "A fresh push did not trigger deployment."
    assert open(flag).read() == "DEPLOYED\n"
    assert not os.path.exists(wrong_flag), "Deployment used /tmp/default_deploy instead of MICRO_DEPLOY_PATH."
    assert os.path.isfile(metrics), "A fresh push did not create the metrics log."
    lines = open(metrics).read().splitlines()
    assert yaml_base in lines, f"Nested added YAML basename was not logged: {lines}"
    assert "inventory" in lines, f"Modified inventory.yml was not logged: {lines}"
    assert non_yaml_base not in lines, f"A non-YAML file was incorrectly logged: {lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
