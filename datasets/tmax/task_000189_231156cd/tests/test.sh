#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import datetime
import json
import os
import re
import secrets
import shutil
import subprocess

HOME = "/home/user"
PROJECT = f"{HOME}/src/network_provisioner"
LOG = f"{HOME}/logs/provision.log"
ROUTES = f"{HOME}/network/routes.batch"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 180)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def active_logrotate_block(content, target):
    lines = [line.split("#", 1)[0].strip() for line in content.splitlines()]
    header = re.compile(r'^\s*["\']?' + re.escape(target) + r'["\']?\s*\{\s*$')
    for index, line in enumerate(lines):
        if header.match(line):
            block = []
            for item in lines[index + 1:]:
                if item == "}":
                    return [entry.lower().split() for entry in block if entry]
                block.append(item)
            raise AssertionError("Unterminated logrotate block for provision.log")
    raise AssertionError("logrotate.conf does not contain an active block for provision.log")


def assert_timestamped_lines(lines, users, start, end):
    assert len(lines) == len(users), f"Expected {len(users)} new log lines, got {lines!r}"
    pattern = re.compile(
        r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] "
        r"Provisioned user (\S+) with subnet (\S+)$"
    )
    for line, user in zip(lines, users):
        match = pattern.fullmatch(line)
        assert match, f"Incorrectly formatted provision log line: {line!r}"
        assert match.group(2) == user["username"]
        assert match.group(3) == user["subnet"]
        timestamp = datetime.datetime.strptime(
            match.group(1), "%Y-%m-%d %H:%M:%S"
        ).replace(tzinfo=datetime.timezone.utc)
        assert start - datetime.timedelta(seconds=2) <= timestamp <= end + datetime.timedelta(seconds=2), (
            f"Timestamp {timestamp} is not the UTC time of this execution"
        )


def cargo_binary():
    metadata = run([
        "cargo", "metadata", "--format-version", "1", "--no-deps",
        "--manifest-path", f"{PROJECT}/Cargo.toml",
    ])
    data = json.loads(metadata.stdout)
    bins = []
    for package in data["packages"]:
        for target in package["targets"]:
            if "bin" in target.get("kind", []):
                bins.append(target["name"])
    assert len(bins) == 1, f"Expected one Rust provisioning binary, found {bins}"
    return os.path.join(data["target_directory"], "release", bins[0])


def assert_real_executable(path):
    assert os.path.isfile(path), f"Release binary missing at {path}"
    assert os.access(path, os.X_OK), f"Release binary is not executable: {path}"
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Cargo release artifact is not a compiled ELF binary"


def test_complete_system():
    repo_path = f"{HOME}/accounts.git"
    assert os.path.isdir(repo_path), f"Bare repo {repo_path} does not exist"
    bare = run(["git", "-C", repo_path, "rev-parse", "--is-bare-repository"])
    assert bare.stdout.strip() == "true", f"{repo_path} is not a bare Git repository"

    hook_path = os.path.join(repo_path, "hooks", "post-receive")
    assert os.path.isfile(hook_path), f"post-receive hook missing at {hook_path}"
    assert os.access(hook_path, os.X_OK), "post-receive hook is not executable"

    cargo_toml = f"{PROJECT}/Cargo.toml"
    assert os.path.isfile(cargo_toml), "Rust project Cargo.toml missing"

    conf_path = f"{HOME}/logrotate.conf"
    assert os.path.isfile(conf_path), "logrotate.conf missing"
    with open(conf_path, encoding="utf-8") as handle:
        content = handle.read()
    lower = content.lower()

    # Preserve the original textual assertions.
    assert "daily" in lower, "logrotate.conf missing 'daily'"
    assert "rotate 5" in lower, "logrotate.conf missing 'rotate 5'"
    assert "compress" in lower, "logrotate.conf missing 'compress'"
    assert "missingok" in lower, "logrotate.conf missing 'missingok'"
    assert "create 0644" in lower or "create 644" in lower, "logrotate.conf missing 'create 0644'"
    assert LOG in content, "logrotate.conf does not target the correct log file"

    # Require those settings to be active directives in the correct block, not comments.
    directives = active_logrotate_block(content, LOG)
    assert ["daily"] in directives
    assert ["rotate", "5"] in directives
    assert ["compress"] in directives
    assert ["missingok"] in directives
    create = [tokens for tokens in directives if tokens and tokens[0] == "create"]
    assert create and len(create[0]) >= 2 and create[0][1] in ("0644", "644"), (
        "The provision.log block must actively specify create 0644"
    )
    debug = subprocess.run(
        ["logrotate", "--debug", "--state", "/tmp/logrotate-audit.state", conf_path],
        capture_output=True, text=True, timeout=60,
    )
    assert debug.returncode == 0, f"Invalid logrotate configuration:\n{debug.stdout}\n{debug.stderr}"

    # Build and execute the Rust artifact directly on unpredictable input.
    run(["cargo", "build", "--release", "--manifest-path", cargo_toml])
    binary = cargo_binary()
    assert_real_executable(binary)

    token = secrets.token_hex(5)
    direct_users = [
        {"username": f"direct_{token}_{i}", "subnet": f"10.{40 + i}.{secrets.randbelow(200) + 1}.0/24"}
        for i in range(3)
    ]
    direct_json = f"/tmp/users-direct-{token}.json"
    with open(direct_json, "w", encoding="utf-8") as handle:
        json.dump(direct_users, handle)

    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    os.makedirs(os.path.dirname(ROUTES), exist_ok=True)
    with open(LOG, "w", encoding="utf-8") as handle:
        handle.write("preexisting audit line\n")
    with open(ROUTES, "w", encoding="utf-8") as handle:
        handle.write("route add 203.0.113.0/24 dev stale0\n")

    start = datetime.datetime.now(datetime.timezone.utc)
    run([binary, direct_json])
    end = datetime.datetime.now(datetime.timezone.utc)

    with open(ROUTES, encoding="utf-8") as handle:
        route_lines = handle.read().splitlines()
    expected_routes = [f"route add {user['subnet']} dev dummy0" for user in direct_users]
    assert route_lines == expected_routes, (
        "Direct execution must truncate routes.batch and write exactly the current input routes"
    )

    with open(LOG, encoding="utf-8") as handle:
        direct_logs = handle.read().splitlines()
    assert direct_logs[0] == "preexisting audit line", "The provisioning log must be appended to"
    assert_timestamped_lines(direct_logs[1:], direct_users, start, end)

    # Exercise the actual push workflow with a second unpredictable data set.
    clone_dir = f"/tmp/test-clone-{token}"
    shutil.rmtree(clone_dir, ignore_errors=True)
    run(["git", "clone", repo_path, clone_dir])
    run(["git", "config", "user.email", "test@example.com"], cwd=clone_dir)
    run(["git", "config", "user.name", "Test User"], cwd=clone_dir)

    hook_users = [
        {"username": f"pushed_{token}_{i}", "subnet": f"172.{20 + i}.{secrets.randbelow(200) + 1}.0/24"}
        for i in range(2)
    ]
    pushed_json = json.dumps(hook_users)
    with open(os.path.join(clone_dir, "users.json"), "w", encoding="utf-8") as handle:
        handle.write(pushed_json)
    run(["git", "add", "users.json"], cwd=clone_dir)
    run(["git", "commit", "-m", f"Audit provisioning {token}"], cwd=clone_dir)

    # Removing all Cargo products requires the hook to recreate a release artifact.
    run(["cargo", "clean", "--manifest-path", cargo_toml])
    assert not os.path.exists(binary)
    start = datetime.datetime.now(datetime.timezone.utc)
    run(["git", "push", "origin", "HEAD:master"], cwd=clone_dir)
    end = datetime.datetime.now(datetime.timezone.utc)

    assert_real_executable(binary)
    worktree_json = f"{HOME}/accounts_worktree/users.json"
    assert os.path.isfile(worktree_json), "The pushed users.json was not checked out into accounts_worktree"
    with open(worktree_json, encoding="utf-8") as handle:
        assert json.load(handle) == hook_users, "accounts_worktree does not contain the pushed configuration"

    with open(ROUTES, encoding="utf-8") as handle:
        pushed_routes = handle.read().splitlines()
    expected_pushed_routes = [f"route add {user['subnet']} dev dummy0" for user in hook_users]
    assert pushed_routes == expected_pushed_routes, (
        "The hook must run provisioning and leave only routes from the newly pushed users.json"
    )

    with open(LOG, encoding="utf-8") as handle:
        all_logs = handle.read().splitlines()
    assert all_logs[:len(direct_logs)] == direct_logs, "The hook must append rather than replace prior audit logs"
    assert_timestamped_lines(all_logs[len(direct_logs):], hook_users, start, end)
PYTEST

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
