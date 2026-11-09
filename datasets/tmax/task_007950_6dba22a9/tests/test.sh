#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest

REPO = "/home/user/router_repo.git"
DEPLOY = "/home/user/router_deploy"
CONF = "/home/user/mock_routes.conf"
LOG = "/home/user/pipeline.log"
EXPECTED_ROUTES = {
    "10.0.5.0/24 via 192.168.50.1",
    "0.0.0.0/0 via 192.168.1.1",
}


def run(cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=check)


def git(*args, cwd=None, check=True):
    return run(["git", "-c", "safe.directory=*", *args], cwd=cwd, check=check)


def assert_routes_exact():
    assert os.path.isfile(CONF), f"Mock routes config {CONF} does not exist."
    with open(CONF, "rb") as f:
        raw = f.read()
    decoded = raw.decode("utf-8")
    lines = decoded.splitlines()
    assert all(line != "" for line in lines), "mock_routes.conf contains blank lines."
    assert len(lines) == 2, "mock_routes.conf should contain exactly two routing entries."
    assert set(lines) == EXPECTED_ROUTES, "mock_routes.conf does not contain exactly the required routes."


def assert_elf_router():
    binary = os.path.join(DEPLOY, "router")
    assert os.path.isfile(binary), f"Compiled binary {binary} does not exist."
    assert os.access(binary, os.X_OK), f"Compiled binary {binary} is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "router is not a compiled ELF executable."


def assert_fixed_router_behavior():
    binary = os.path.join(DEPLOY, "router")
    result1 = run([binary, "0.0.0.0/0"], check=False)
    assert result1.returncode == 0, "Router program failed to execute."
    assert result1.stdout.strip() == "192.168.1.1", "Router program did not output the correct NEXT_HOP for 0.0.0.0/0."

    result2 = run([binary, "10.99.99.0/24"], check=False)
    assert result2.returncode == 0, "Router program failed to execute."
    assert result2.stdout.strip() == "DROP", "Router program did not output DROP for an unknown network."


def test_01_bare_repo_is_real_and_has_master_commit():
    assert os.path.isdir(REPO), "Bare Git repository /home/user/router_repo.git does not exist."
    assert os.path.isfile(os.path.join(REPO, "HEAD")), f"{REPO} has no HEAD file."
    result = git("--git-dir", REPO, "rev-parse", "--is-bare-repository")
    assert result.stdout.strip() == "true", f"{REPO} is not a valid bare Git repository."
    assert git("--git-dir", REPO, "cat-file", "-t", "refs/heads/master").stdout.strip() == "commit", "The bare repository has no master commit."

    for name in ("router.c", "config_routes.sh", "deploy.sh"):
        entry = git("--git-dir", REPO, "ls-tree", "refs/heads/master", "--", name).stdout.strip()
        assert entry, f"master does not track required file {name}."
        fields = entry.split(None, 3)
        assert fields[1] == "blob", f"Tracked path {name} is not a regular Git blob."
        if name.endswith(".sh"):
            assert fields[0] == "100755", f"Tracked script {name} is not executable."


def test_02_hook_and_initial_pipeline_artifacts_exist():
    hook = os.path.join(REPO, "hooks", "post-receive")
    assert os.path.isfile(hook), "The post-receive hook does not exist."
    assert os.access(hook, os.X_OK), "The post-receive hook is not executable."
    assert os.path.isdir(DEPLOY), "Deployment directory /home/user/router_deploy does not exist."

    assert_elf_router()
    assert os.path.isfile(LOG), f"Pipeline log {LOG} does not exist."
    with open(LOG, "r") as f:
        content = f.read()
    assert "PIPELINE_SUCCESS: 192.168.50.1" in content, "Pipeline log does not contain the expected success message."
    assert_routes_exact()
    assert_fixed_router_behavior()


def test_03_config_routes_is_content_idempotent():
    script = os.path.join(DEPLOY, "config_routes.sh")
    assert os.path.isfile(script), f"Script {script} does not exist."

    with open(CONF, "rb") as f:
        before = f.read()
    lines_before = len(before.splitlines())

    for _ in range(10):
        result = run(["bash", script], check=False)
        assert result.returncode == 0, f"config_routes.sh failed: {result.stderr}"
        with open(CONF, "rb") as f:
            after = f.read()
        lines_after = len(after.splitlines())
        assert lines_before == lines_after, "config_routes.sh is not idempotent; line count changed after re-running."
        assert after == before, "config_routes.sh changes the routing file when rerun."
        assert_routes_exact()


def test_04_deploy_script_rebuilds_and_appends_success():
    deploy_script = os.path.join(DEPLOY, "deploy.sh")
    config_script = os.path.join(DEPLOY, "config_routes.sh")
    assert os.path.isfile(deploy_script), "deploy.sh is missing from the deployment directory."
    assert os.access(deploy_script, os.X_OK), "deploy.sh is not executable."
    assert os.access(config_script, os.X_OK), "config_routes.sh is not executable."

    with open(LOG, "rb") as f:
        log_before = f.read()
    old_successes = log_before.count(b"PIPELINE_SUCCESS: 192.168.50.1")

    os.remove(os.path.join(DEPLOY, "router"))
    os.remove(CONF)
    result = run(["./deploy.sh"], cwd=DEPLOY, check=False)
    assert result.returncode == 0, f"deploy.sh failed: {result.stdout}{result.stderr}"

    assert_elf_router()
    assert_routes_exact()
    with open(LOG, "rb") as f:
        log_after = f.read()
    assert log_after.startswith(log_before), "deploy.sh overwrote pipeline.log instead of appending to it."
    assert log_after.count(b"PIPELINE_SUCCESS: 192.168.50.1") == old_successes + 1, "deploy.sh did not append exactly one success message."


def test_05_real_push_runs_hook_extracts_commit_and_builds_source():
    token = uuid.uuid4().hex
    marker = f"/home/user/.verifier_deploy_marker_{token}"

    with tempfile.TemporaryDirectory() as tmp:
        clone = os.path.join(tmp, "clone")
        git("clone", REPO, clone)
        git("checkout", "master", cwd=clone)
        git("config", "user.email", "verifier@example.invalid", cwd=clone)
        git("config", "user.name", "Verifier", cwd=clone)

        router_source = os.path.join(clone, "router.c")
        with open(router_source, "a") as f:
            f.write(f'\nconst char verifier_build_token_{token}[] = "{token}";\n')

        deploy_source = os.path.join(clone, "deploy.sh")
        with open(deploy_source, "r") as f:
            deploy_text = f.read()
        assert deploy_text.startswith("#!"), "deploy.sh lacks an executable-script shebang."
        first, sep, rest = deploy_text.partition("\n")
        instrumented = first + "\n" + f"printf '%s\\n' '{token}' > '{marker}'\n" + rest
        with open(deploy_source, "w") as f:
            f.write(instrumented)

        git("add", "router.c", "deploy.sh", cwd=clone)
        git("commit", "-m", f"Verifier hook exercise {token}", cwd=clone)

        if os.path.lexists(marker):
            os.remove(marker)
        if os.path.isdir(DEPLOY):
            shutil.rmtree(DEPLOY)
        if os.path.exists(CONF):
            os.remove(CONF)
        if os.path.exists(LOG):
            os.remove(LOG)

        pushed = git("push", "origin", "HEAD:master", cwd=clone, check=False)
        assert pushed.returncode == 0, f"Push to master failed: {pushed.stdout}{pushed.stderr}"

        assert os.path.isfile(marker), "The pushed deploy.sh was not executed by the post-receive hook."
        with open(marker, "r") as f:
            assert f.read().strip() == token

        assert os.path.isdir(DEPLOY), "The post-receive hook did not recreate the deployment directory."
        for name in ("router.c", "config_routes.sh", "deploy.sh"):
            with open(os.path.join(clone, name), "rb") as expected_file:
                expected = expected_file.read()
            with open(os.path.join(DEPLOY, name), "rb") as deployed_file:
                actual = deployed_file.read()
            assert actual == expected, f"The hook did not extract pushed {name} into the deployment directory."

        assert_elf_router()
        with open(os.path.join(DEPLOY, "router"), "rb") as f:
            binary_data = f.read()
        assert token.encode() in binary_data, "The deployed router binary was not compiled from the pushed router.c."

        assert_routes_exact()
        assert os.path.isfile(LOG), "The hook did not generate pipeline.log."
        with open(LOG, "r") as f:
            lines = f.read().splitlines()
        assert lines == ["PIPELINE_SUCCESS: 192.168.50.1"], "The fresh hook run did not log exactly one pipeline success."
        assert_fixed_router_behavior()


def test_06_router_uses_arbitrary_configuration_inputs():
    binary = os.path.join(DEPLOY, "router")
    seed = uuid.uuid4().int
    destinations = [
        f"10.{(seed >> 8) % 200 + 20}.{seed % 200 + 20}.0/24",
        f"172.{(seed >> 16) % 15 + 16}.{(seed >> 24) % 200 + 20}.0/24",
        f"192.0.2.{seed % 200 + 1}/32",
    ]
    next_hops = [
        f"198.51.100.{seed % 200 + 1}",
        f"203.0.113.{(seed >> 8) % 200 + 1}",
        f"192.0.2.{(seed >> 16) % 200 + 1}",
    ]
    unknown = f"100.64.{(seed >> 32) % 200}.0/24"

    try:
        with open(CONF, "w") as f:
            for destination, next_hop in zip(destinations, next_hops):
                f.write(f"{destination} via {next_hop}\n")

        for destination, next_hop in zip(destinations, next_hops):
            result = run([binary, destination], check=False)
            assert result.returncode == 0, f"router failed for generated destination {destination}."
            assert result.stdout.strip() == next_hop, f"router did not read the generated route for {destination}."

        missing = run([binary, unknown], check=False)
        assert missing.returncode == 0
        assert missing.stdout.strip() == "DROP", "router did not return DROP for a generated unknown route."

        no_arg = run([binary], check=False)
        two_args = run([binary, destinations[0], destinations[1]], check=False)
        assert no_arg.returncode != 0, "router accepted zero command-line arguments."
        assert two_args.returncode != 0, "router accepted more than one command-line argument."
    finally:
        result = run(["bash", os.path.join(DEPLOY, "config_routes.sh")], check=False)
        assert result.returncode == 0
        assert_routes_exact()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
