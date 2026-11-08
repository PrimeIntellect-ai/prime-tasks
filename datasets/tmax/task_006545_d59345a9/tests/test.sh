#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import shutil
import stat
import subprocess
import time
import uuid

USER = "user"
USER_INFO = pwd.getpwnam(USER)
USER_ENV = {
    "HOME": USER_INFO.pw_dir,
    "USER": USER,
    "LOGNAME": USER,
    "XDG_RUNTIME_DIR": f"/run/user/{USER_INFO.pw_uid}",
    "DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{USER_INFO.pw_uid}/bus",
}


def run_as_user(args, check=False, timeout=60):
    cmd = ["runuser", "-u", USER, "--", "env"]
    cmd.extend(f"{key}={value}" for key, value in USER_ENV.items())
    cmd.extend(args)
    return subprocess.run(cmd, capture_output=True, text=True, check=check, timeout=timeout)


def test_fstab_configuration():
    fstab_path = "/home/user/app_storage.fstab"
    assert os.path.exists(fstab_path), f"{fstab_path} does not exist."

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.startswith("#")]
    assert len(lines) == 1, f"{fstab_path} should contain exactly one valid fstab line."

    parts = lines[0].split()
    assert len(parts) == 6, f"fstab line does not have 6 fields: {lines[0]}"
    assert parts[0] == "UUID=9b1c990b-8f19-4b6d-9799-a3b043b177d4", "Incorrect UUID."
    assert parts[1] == "/home/user/app_data", "Incorrect mount point."
    assert parts[2] == "ext4", "Incorrect filesystem type."
    assert parts[3] == "defaults,nofail", "Incorrect mount options."
    assert parts[4] == "0", "Incorrect dump number."
    assert parts[5] == "2", "Incorrect pass number."


def test_app_data_directory_exists():
    assert os.path.isdir("/home/user/app_data"), "/home/user/app_data directory does not exist."


def test_git_bare_repo_and_hook():
    repo_dir = "/home/user/deploy.git"
    assert os.path.isdir(repo_dir), f"{repo_dir} does not exist."

    result = subprocess.run(["git", "-C", repo_dir, "rev-parse", "--is-bare-repository"], capture_output=True, text=True)
    assert result.stdout.strip() == "true", f"{repo_dir} is not a bare Git repository."

    hook_path = os.path.join(repo_dir, "hooks", "post-receive")
    assert os.path.exists(hook_path), f"Git hook {hook_path} does not exist."
    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Git hook {hook_path} is not executable."

    with open(hook_path, "r") as f:
        hook_content = f.read()
    assert "checkout" in hook_content and "main" in hook_content, "Hook does not seem to checkout the main branch."
    assert "/home/user/app_src" in hook_content, "Hook does not specify the correct working tree directory."
    assert "systemctl --user restart app-worker.service" in hook_content or "systemctl --user restart app-worker" in hook_content, "Hook does not restart the app-worker service."


def test_systemd_service_file():
    service_path = "/home/user/.config/systemd/user/app-worker.service"
    assert os.path.exists(service_path), f"{service_path} does not exist."

    with open(service_path, "r") as f:
        content = f.read()

    assert "Restart=on-failure" in content, "Service file missing 'Restart=on-failure'."
    assert "podman run" in content, "Service file missing 'podman run' command."
    assert "-v /home/user/app_src:/app" in content or "--volume /home/user/app_src:/app" in content or "--volume=/home/user/app_src:/app" in content, "Service file missing volume mount for /app."
    assert "-v /home/user/app_data:/data" in content or "--volume /home/user/app_data:/data" in content or "--volume=/home/user/app_data:/data" in content, "Service file missing volume mount for /data."
    assert "python:3.10-alpine" in content, "Service file missing the correct container image."
    assert "python /app/main.py" in content, "Service file missing the correct execution command."

    enabled = run_as_user(["systemctl", "--user", "is-enabled", "app-worker.service"])
    assert enabled.stdout.strip() == "enabled", "app-worker.service is not enabled."

    fragment = run_as_user(["systemctl", "--user", "show", "app-worker.service", "-p", "FragmentPath", "--value"])
    assert fragment.stdout.strip() == service_path, "The active user unit was not loaded from the required service file."

    restart = run_as_user(["systemctl", "--user", "show", "app-worker.service", "-p", "Restart", "--value"])
    assert restart.stdout.strip() == "on-failure", "The loaded unit does not use Restart=on-failure."

    exec_start = run_as_user(["systemctl", "--user", "show", "app-worker.service", "-p", "ExecStart", "--value"]).stdout
    for required in ("podman", "run", "python:3.10-alpine", "/home/user/app_src:/app", "/home/user/app_data:/data", "python", "/app/main.py"):
        assert required in exec_start, f"The loaded unit's ExecStart is missing {required!r}."


def test_pipeline_with_fresh_push():
    nonce = uuid.uuid4().hex
    workspace = f"/home/user/.verifier-workspace-{nonce}"
    os.mkdir(workspace)
    os.chown(workspace, USER_INFO.pw_uid, USER_INFO.pw_gid)

    try:
        clone = run_as_user(["git", "clone", "--branch", "main", "/home/user/deploy.git", workspace], timeout=60)
        assert clone.returncode == 0, f"Could not clone main from deploy.git: {clone.stderr}"

        source = (
            "import time\n\n"
            "with open(\"/data/deploy_log.txt\", \"a\") as f:\n"
            "    f.write(\"Update deployed successfully\\n\")\n"
            f"    f.write(\"verification nonce: {nonce}\\n\")\n\n"
            "print(\"Application running...\")\n"
            "time.sleep(3600)\n"
        )
        main_path = os.path.join(workspace, "main.py")
        with open(main_path, "w") as f:
            f.write(source)
        os.chown(main_path, USER_INFO.pw_uid, USER_INFO.pw_gid)

        run_as_user(["git", "-C", workspace, "config", "user.name", "Verifier"], check=True)
        run_as_user(["git", "-C", workspace, "config", "user.email", "verifier@localhost"], check=True)
        run_as_user(["git", "-C", workspace, "add", "main.py"], check=True)
        run_as_user(["git", "-C", workspace, "commit", "-m", f"verification deployment {nonce}"], check=True)
        expected_commit = run_as_user(["git", "-C", workspace, "rev-parse", "HEAD"], check=True).stdout.strip()

        # Remove every pre-existing source of the expected final state. A fresh push
        # must check out this commit, restart the user unit, and launch its container.
        stopped = run_as_user(["systemctl", "--user", "stop", "app-worker.service"], timeout=30)
        assert stopped.returncode == 0, f"Could not stop app-worker.service before pipeline test: {stopped.stderr}"
        run_as_user(["podman", "rm", "-f", "app-worker"], timeout=30)
        log_path = "/home/user/app_data/deploy_log.txt"
        if os.path.exists(log_path):
            os.remove(log_path)

        inactive = run_as_user(["systemctl", "--user", "is-active", "app-worker.service"])
        assert inactive.stdout.strip() != "active", "Service remained active after being stopped."
        assert "app-worker" not in run_as_user(["podman", "ps", "--format", "{{.Names}}"]).stdout.splitlines()

        pushed = run_as_user(["git", "-C", workspace, "push", "origin", "HEAD:main"], timeout=90)
        assert pushed.returncode == 0, f"Fresh push to main failed or its post-receive hook failed: {pushed.stderr}"

        deadline = time.time() + 45
        while time.time() < deadline:
            active = run_as_user(["systemctl", "--user", "is-active", "app-worker.service"]).stdout.strip() == "active"
            running = "app-worker" in run_as_user(["podman", "ps", "--format", "{{.Names}}"]).stdout.splitlines()
            logged = os.path.exists(log_path) and nonce in open(log_path).read()
            if active and running and logged:
                break
            time.sleep(1)
        else:
            raise AssertionError("Fresh push did not check out the commit, restart the service, run the container, and produce the nonce log.")

        checked_out = subprocess.run(["git", "-C", "/home/user/app_src", "rev-parse", "HEAD"], capture_output=True, text=True)
        assert checked_out.returncode == 0 and checked_out.stdout.strip() == expected_commit, "post-receive did not check out the freshly pushed main commit."
        with open("/home/user/app_src/main.py") as f:
            assert f.read() == source, "app_src/main.py is not the file from the freshly pushed commit."

        inspected = run_as_user(["podman", "inspect", "app-worker"], check=True)
        info = json.loads(inspected.stdout)[0]
        assert info.get("State", {}).get("Running") is True, "app-worker container is not running."
        config = info.get("Config", {})
        image = config.get("Image", "") or info.get("ImageName", "")
        assert "python:3.10-alpine" in image, "Running app-worker does not use python:3.10-alpine."
        assert config.get("WorkingDir") == "/app", "Running app-worker does not use /app as its working directory."
        command = " ".join(config.get("Cmd") or [])
        assert "python" in command and "/app/main.py" in command, "Running app-worker does not execute python /app/main.py."
        mounts = {(m.get("Source"), m.get("Destination")) for m in info.get("Mounts", [])}
        assert ("/home/user/app_src", "/app") in mounts, "Running app-worker lacks the required /app bind mount."
        assert ("/home/user/app_data", "/data") in mounts, "Running app-worker lacks the required /data bind mount."
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


def test_service_is_active():
    result = run_as_user(["systemctl", "--user", "is-active", "app-worker.service"])
    assert result.stdout.strip() == "active", "app-worker.service is not active."


def test_podman_container_running():
    result = run_as_user(["podman", "ps", "--format", "{{.Names}}"])
    containers = result.stdout.strip().splitlines()
    assert "app-worker" in containers, "Podman container 'app-worker' is not running."


def test_deploy_log_content():
    log_path = "/home/user/app_data/deploy_log.txt"
    assert os.path.exists(log_path), f"{log_path} does not exist. The pipeline might not have triggered successfully."
    with open(log_path, "r") as f:
        content = f.read()
    assert "Update deployed successfully" in content, f"Expected message not found in {log_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
