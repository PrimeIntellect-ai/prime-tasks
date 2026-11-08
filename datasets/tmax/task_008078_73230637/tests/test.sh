#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
import time
from datetime import datetime
from pathlib import Path


def run_git(args, cwd, check=True):
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=check,
        capture_output=True,
        text=True,
    )


def remove_if_present(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def test_post_receive_hook_execution():
    repo_path = Path("/home/user/dashboard-repo.git")
    deploy_path = Path("/home/user/dashboards_deployed")
    reloaded_file = Path("/home/user/service_reloaded.txt")
    log_file = Path("/home/user/deploy.log")
    pid_file = Path("/home/user/dashboard.pid")

    hook_path = repo_path / "hooks" / "post-receive"
    assert hook_path.is_file(), "post-receive hook file is missing."
    assert os.access(hook_path, os.X_OK), "post-receive hook is not executable."

    token = secrets.token_hex(12)
    retained_name = f"dashboard_{token}.json"
    root_name = f"summary_{token}.json"
    nested_dir = f"group_{token}"
    nested_name = f"detail_{token}.json"
    obsolete_name = f"obsolete_{token}.json"

    final_contents = {
        retained_name: (f'{{"token":"{token}","revision":2}}\n').encode(),
        root_name: (f'{{"summary":"{token}"}}\n').encode(),
        f"{nested_dir}/{nested_name}": (f'{{"nested":"{token}"}}\n').encode(),
    }

    with tempfile.TemporaryDirectory() as temp_dir:
        work = Path(temp_dir)
        run_git(["init"], work)
        run_git(["checkout", "-b", "master"], work)
        run_git(["config", "user.email", "test@example.com"], work)
        run_git(["config", "user.name", "Test User"], work)

        (work / retained_name).write_text('{"revision":1}\n')
        (work / obsolete_name).write_text('{"obsolete":true}\n')
        run_git(["add", retained_name, obsolete_name], work)
        run_git(["commit", "-m", "Initial randomized dashboards"], work)

        (work / obsolete_name).unlink()
        for relative, content in final_contents.items():
            target = work / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        run_git(["add", "-A"], work)
        run_git(["commit", "-m", "Latest randomized dashboards"], work)
        expected_commit = run_git(["rev-parse", "HEAD"], work).stdout.strip()

        # Establish fresh pre-push state so old markers, logs, or deployments cannot pass.
        if os.path.lexists(deploy_path):
            if deploy_path.is_symlink() or not deploy_path.is_dir():
                os.unlink(deploy_path)
            else:
                shutil.rmtree(deploy_path)
        deploy_path.mkdir(parents=True)
        stale_dir = deploy_path / f"stale_{token}"
        stale_dir.mkdir()
        (stale_dir / "must_be_removed.json").write_text('{"stale":true}\n')

        assert pid_file.is_file(), "Dashboard service PID file is missing"
        pid = int(pid_file.read_text().strip())
        os.kill(pid, 0)

        # Allow any earlier pending signal to settle, then remove its marker.
        remove_if_present(reloaded_file)
        time.sleep(1.25)
        remove_if_present(reloaded_file)

        baseline = f"verifier-baseline-{token}\n".encode()
        log_file.write_bytes(baseline)

        run_git(["remote", "add", "origin", str(repo_path)], work)
        push_started = time.time()
        push_result = run_git(["push", "--force", "origin", "master:master"], work, check=False)
        push_finished = time.time()
        assert push_result.returncode == 0, f"Git push failed: {push_result.stderr}"

    deployed_commit = run_git(["rev-parse", "refs/heads/master"], repo_path).stdout.strip()
    assert deployed_commit == expected_commit, "The pushed master branch is not the expected revision"

    # The deployed tree must exactly mirror the latest master tree, including contents.
    assert deploy_path.is_dir() and not deploy_path.is_symlink(), f"{deploy_path} is not a directory"
    actual_files = set()
    actual_dirs = set()
    for root, dirnames, filenames in os.walk(deploy_path, followlinks=False):
        root_path = Path(root)
        for name in dirnames:
            path = root_path / name
            assert not path.is_symlink(), f"Unexpected symlink deployed: {path}"
            actual_dirs.add(path.relative_to(deploy_path).as_posix())
        for name in filenames:
            path = root_path / name
            assert path.is_file() and not path.is_symlink(), f"Unexpected non-regular deployed entry: {path}"
            actual_files.add(path.relative_to(deploy_path).as_posix())

    expected_files = set(final_contents)
    expected_dirs = {nested_dir}
    assert actual_files == expected_files, f"Deployed files do not mirror master: {actual_files}"
    assert actual_dirs == expected_dirs, f"Deployed directories do not mirror master: {actual_dirs}"
    for relative, expected in final_contents.items():
        assert (deploy_path / relative).read_bytes() == expected, f"Wrong deployed content for {relative}"

    # Directory and every deployed directory/file must be mode 750.
    all_paths = [deploy_path]
    all_paths.extend(deploy_path / relative for relative in sorted(actual_dirs | actual_files))
    for path in all_paths:
        mode = stat.S_IMODE(os.lstat(path).st_mode)
        assert mode == 0o750, f"Permissions for {path} are not 750 (found {oct(mode)})"

    # Wait for the mock service's asynchronous SIGHUP trap and require a fresh marker.
    deadline = time.time() + 6
    while time.time() < deadline:
        if reloaded_file.is_file() and reloaded_file.stat().st_mtime >= push_started - 0.1:
            break
        time.sleep(0.1)
    assert reloaded_file.is_file(), "SIGHUP was not sent to the dashboard service"
    assert reloaded_file.read_text().strip() == "Reloaded", "Dashboard reload marker is invalid"
    assert reloaded_file.stat().st_mtime >= push_started - 0.1, "Reload marker predates the tested push"

    # Require the tested push to append exactly one correctly formatted, current entry.
    assert log_file.is_file(), f"Audit log file {log_file} is missing"
    log_bytes = log_file.read_bytes()
    assert log_bytes.startswith(baseline), "The hook did not append to the existing audit log"
    appended = log_bytes[len(baseline):].decode()
    lines = appended.splitlines()
    assert len(lines) == 1, f"Expected exactly one appended log entry, found {len(lines)}"
    last_log = lines[0]
    log_pattern = r'^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] Dashboards reloaded$'
    assert re.match(log_pattern, last_log), f"Log entry format is incorrect. Found: {last_log}"
    timestamp = datetime.strptime(last_log[1:20], "%Y-%m-%d %H:%M:%S")
    logged_time = time.mktime(timestamp.timetuple())
    assert push_started - 2 <= logged_time <= max(push_finished, time.time()) + 2, "Log entry is not from the tested push"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
