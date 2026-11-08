#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import grp
import re
import stat
import subprocess
import time
import uuid

USER = pwd.getpwnam("user")
UID = USER.pw_uid
GID = USER.pw_gid
HOME = "/home/user"


def assert_user_owned(path):
    st = os.stat(path, follow_symlinks=False)
    assert st.st_uid == UID, f"{path} is not owned by user"
    assert st.st_gid == GID, f"{path} is not owned by group user"


def run_user(args, cwd=None, check=False, timeout=30):
    runtime = f"/run/user/{UID}"
    env_args = [
        f"HOME={HOME}",
        f"USER=user",
        f"LOGNAME=user",
        f"XDG_RUNTIME_DIR={runtime}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus",
    ]
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", *env_args, *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        raise AssertionError(
            f"Command failed: {args}\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result


def systemctl_user(*args):
    return run_user(["systemctl", "--user", *args], timeout=20)


def unit_values(content, section, key):
    current = None
    values = []
    logical = ""
    lines = content.splitlines()
    combined = []
    for raw in lines:
        if logical:
            logical += raw.lstrip()
        else:
            logical = raw
        if logical.rstrip().endswith("\\"):
            logical = logical.rstrip()[:-1] + " "
            continue
        combined.append(logical)
        logical = ""
    if logical:
        combined.append(logical)

    for raw in combined:
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        match = re.fullmatch(r"\[([^]]+)\]", line)
        if match:
            current = match.group(1)
            continue
        if current == section and "=" in line:
            name, value = line.split("=", 1)
            if name.strip() == key:
                values.extend(value.split())
    return values


def test_systemd_service_dependency_and_runtime_state():
    operator_path = "/home/user/.config/systemd/user/manifest-operator.service"
    api_path = "/home/user/.config/systemd/user/k8s-mock-api.service"
    assert os.path.isfile(operator_path), f"Missing {operator_path}"
    assert os.path.isfile(api_path), f"Missing {api_path}"
    assert_user_owned(operator_path)
    assert_user_owned(api_path)

    with open(operator_path, "r") as f:
        content = f.read()

    # Preserve the original textual assertions.
    assert re.search(r"After=.*k8s-mock-api\.service", content), "manifest-operator.service is missing After=k8s-mock-api.service"
    assert re.search(r"(Requires|Wants)=.*k8s-mock-api\.service", content), "manifest-operator.service is missing Requires=k8s-mock-api.service"

    # Wants= is not equivalent to the required dependency.
    assert "k8s-mock-api.service" in unit_values(content, "Unit", "After"), "The API service must be in After="
    assert "k8s-mock-api.service" in unit_values(content, "Unit", "Requires"), "The API service must be in Requires= (Wants= is insufficient)"

    for service in ("k8s-mock-api.service", "manifest-operator.service"):
        enabled = systemctl_user("is-enabled", service)
        assert enabled.returncode == 0 and enabled.stdout.strip() == "enabled", (
            f"{service} is not enabled\nstdout: {enabled.stdout}\nstderr: {enabled.stderr}"
        )
        active = systemctl_user("is-active", service)
        assert active.returncode == 0 and active.stdout.strip() == "active", (
            f"{service} is not active\nstdout: {active.stdout}\nstderr: {active.stderr}"
        )

    shown = systemctl_user(
        "show", "manifest-operator.service",
        "--property=After", "--property=Requires", "--property=NeedDaemonReload"
    )
    assert shown.returncode == 0, f"Cannot inspect loaded user unit: {shown.stderr}"
    properties = {}
    for line in shown.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            properties[key] = value
    assert "k8s-mock-api.service" in properties.get("After", "").split(), "Loaded unit lacks the required After= ordering"
    assert "k8s-mock-api.service" in properties.get("Requires", "").split(), "Loaded unit lacks the required Requires= dependency"
    assert properties.get("NeedDaemonReload") == "no", "The user systemd daemon has not been reloaded after editing the unit"


def test_git_hook_and_expect_script():
    workspace_repo = "/home/user/workspace/k8s-manifests"
    expect_script = "/home/user/auto-push.exp"
    wrapper = "/home/user/push-manifests.sh"
    hook = "/home/user/k8s-manifests.git/hooks/post-receive"
    hook_log = "/home/user/operator-logs/hook.log"
    bare_repo = "/home/user/k8s-manifests.git"

    assert os.path.isfile(expect_script) and not os.path.islink(expect_script), f"Missing regular expect script at {expect_script}"
    assert os.path.isfile(hook) and not os.path.islink(hook), f"Missing regular hook at {hook}"
    assert bool(os.stat(expect_script).st_mode & stat.S_IXUSR), f"{expect_script} is not executable"
    assert bool(os.stat(hook).st_mode & stat.S_IXUSR), f"{hook} is not executable"
    assert_user_owned(expect_script)
    assert_user_owned(hook)
    assert_user_owned("/home/user/operator-logs")

    with open(expect_script, "r") as f:
        expect_content = f.read()
    first_line = expect_content.splitlines()[0] if expect_content.splitlines() else ""
    assert re.match(r"^#!\s*(?:/usr/bin/expect|/usr/bin/env\s+(?:-S\s+)?expect)(?:\s|$)", first_line), "auto-push.exp must be an Expect script"
    assert re.search(r"\bspawn\s+(?:--\s+)?/home/user/push-manifests\.sh(?:\s|$)", expect_content), "Expect script must spawn /home/user/push-manifests.sh"
    assert "Deploy Passphrase: " in expect_content, "Expect script must wait for the exact deployment prompt"
    assert "k8s-oper-2024" in expect_content and re.search(r"k8s-oper-2024(?:\\r|\\015)", expect_content), "Expect script must send the required passphrase followed by carriage return"
    assert re.search(r"\bexpect\b[^\n]*(?:eof|wait)|\bwait\b", expect_content, re.I), "Expect script must wait for the spawned process to finish"

    if os.path.lexists(hook_log):
        assert os.path.isfile(hook_log) and not os.path.islink(hook_log), "hook.log must be a regular file"
    with open(hook_log, "w"):
        pass
    os.chown(hook_log, UID, GID)

    token = uuid.uuid4().hex
    config_file = os.path.join(workspace_repo, "config.yaml")
    with open(config_file, "a") as f:
        f.write(f"\n# verifier update {token}\n")
    run_user([
        "git", "-c", "user.name=Verifier", "-c", "user.email=verifier@example.invalid",
        "commit", "-am", f"verifier update {token}"
    ], cwd=workspace_repo, check=True)
    head = run_user(["git", "rev-parse", "HEAD"], cwd=workspace_repo, check=True).stdout.strip()

    with open(wrapper, "rb") as f:
        original_wrapper = f.read()
    original_stat = os.stat(wrapper)
    marker = f"/tmp/auto-push-marker-{token}"

    success_wrapper = f'''#!/bin/bash
cd /home/user/workspace/k8s-manifests || exit 70
echo -n "Deploy Passphrase: "
IFS= read -r pass
echo
[ "$pass" = "k8s-oper-2024" ] || exit 71
printf '%s\\n' "$pass" > {marker}
git push origin HEAD:refs/heads/main
'''
    failure_wrapper = '''#!/bin/bash
echo -n "Deploy Passphrase: "
IFS= read -r pass
echo
[ "$pass" = "k8s-oper-2024" ] || exit 72
exit 23
'''

    try:
        with open(wrapper, "w") as f:
            f.write(success_wrapper)
        os.chown(wrapper, UID, GID)
        os.chmod(wrapper, 0o755)

        # Execute the submitted artifact directly, as required by the task.
        result = run_user([expect_script], cwd=workspace_repo, timeout=40)
        assert result.returncode == 0, (
            f"Expect script failed with return code {result.returncode}\n"
            f"Output: {result.stdout}\nError: {result.stderr}"
        )
        assert os.path.isfile(marker), "The Expect script did not spawn the required wrapper"
        with open(marker) as f:
            assert f.read().strip() == "k8s-oper-2024", "The wrapper did not receive the exact passphrase"

        remote_main = subprocess.run(
            ["git", "--git-dir", bare_repo, "rev-parse", "refs/heads/main"],
            capture_output=True, text=True, check=True
        ).stdout.strip()
        assert remote_main == head, "The automated deployment did not actually push the workspace HEAD"

        with open(hook_log) as f:
            lines = f.read().splitlines()
        assert f"HOOK_TRIGGERED: {head}" in lines, f"Hook log does not contain exact line 'HOOK_TRIGGERED: {head}'"

        # Exercise the hook on another real ref update, independently of auto-push.
        second_token = uuid.uuid4().hex
        with open(config_file, "a") as f:
            f.write(f"# second verifier update {second_token}\n")
        run_user([
            "git", "-c", "user.name=Verifier", "-c", "user.email=verifier@example.invalid",
            "commit", "-am", f"second verifier update {second_token}"
        ], cwd=workspace_repo, check=True)
        second_head = run_user(["git", "rev-parse", "HEAD"], cwd=workspace_repo, check=True).stdout.strip()
        test_ref = f"refs/heads/verifier-{second_token}"
        run_user(["git", "push", "origin", f"HEAD:{test_ref}"], cwd=workspace_repo, check=True)
        with open(hook_log) as f:
            lines = f.read().splitlines()
        assert f"HOOK_TRIGGERED: {second_head}" in lines, "The post-receive hook did not process Git-provided stdin for an independent push"

        assert_user_owned(hook_log)

        # A successful automation script must not report success when its child fails.
        with open(wrapper, "w") as f:
            f.write(failure_wrapper)
        os.chown(wrapper, UID, GID)
        os.chmod(wrapper, 0o755)
        failed = run_user([expect_script], cwd=workspace_repo, timeout=20)
        assert failed.returncode != 0, "Expect script does not propagate failure of push-manifests.sh"
    finally:
        with open(wrapper, "wb") as f:
            f.write(original_wrapper)
        os.chown(wrapper, original_stat.st_uid, original_stat.st_gid)
        os.chmod(wrapper, stat.S_IMODE(original_stat.st_mode))
        if os.path.exists(marker):
            os.unlink(marker)


def test_logrotate_config():
    logrotate_conf = "/home/user/logrotate.conf"
    assert os.path.isfile(logrotate_conf) and not os.path.islink(logrotate_conf), f"Missing {logrotate_conf}"
    assert_user_owned(logrotate_conf)

    with open(logrotate_conf, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "/home/user/operator-logs/*.log" in content, "Logrotate config does not target /home/user/operator-logs/*.log"
    assert "daily" in content, "Logrotate config missing 'daily'"
    assert re.search(r"rotate\s+3", content), "Logrotate config missing 'rotate 3'"
    assert "compress" in content, "Logrotate config missing 'compress'"

    uncommented = re.sub(r"(?m)#.*$", "", content)
    block_match = re.search(r"(?m)^\s*/home/user/operator-logs/\*\.log\s*\{([^}]*)\}", uncommented, re.S)
    assert block_match, "No valid logrotate block for /home/user/operator-logs/*.log"
    directives = [line.strip() for line in block_match.group(1).splitlines() if line.strip()]
    assert "daily" in directives, "The target log block is not configured for daily rotation"
    assert any(re.fullmatch(r"rotate\s+3", line) for line in directives), "The target log block must keep exactly 3 copies"
    assert "compress" in directives, "The target log block does not enable compression"
    assert "nocompress" not in directives, "The target log block disables compression"
    assert not any(line in {"hourly", "weekly", "monthly", "yearly"} for line in directives), "A conflicting rotation interval is configured"
    assert not any(re.fullmatch(r"rotate\s+(?!3(?:\s|$))\d+", line) for line in directives), "A conflicting rotate count is configured"

    log_dir = "/home/user/operator-logs"
    old_mode = stat.S_IMODE(os.stat(log_dir).st_mode)
    try:
        os.chmod(log_dir, 0o755)
        checked = subprocess.run(
            ["logrotate", "--debug", logrotate_conf],
            capture_output=True, text=True, timeout=20
        )
    finally:
        os.chmod(log_dir, old_mode)
    output = checked.stdout + checked.stderr
    assert checked.returncode == 0 and not re.search(r"(?im)^error:", output), f"Invalid logrotate configuration:\n{output}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
