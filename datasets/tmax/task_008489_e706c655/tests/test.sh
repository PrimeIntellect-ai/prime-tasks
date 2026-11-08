#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import stat
import subprocess
import tempfile
import uuid

HOME = "/home/user"
TELEMETRY = f"{HOME}/telemetry_data"
SOURCE = f"{HOME}/sensor_processor.c"
PROCESSOR = f"{HOME}/sensor_processor"
REPO = f"{HOME}/iot_sync_repo"
HOOK = f"{REPO}/.git/hooks/pre-commit"
SCRIPT = f"{HOME}/sync_telemetry.sh"
REPORT = f"{REPO}/telemetry_report.txt"
REQUIRED = "[IoT-Sync] Locale: en_US.UTF-8, Timezone: UTC"
USER = pwd.getpwnam("user")


def as_user():
    os.initgroups(USER.pw_name, USER.pw_gid)
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_user(args, **kwargs):
    env = os.environ.copy()
    env.update({"HOME": HOME, "USER": "user", "LOGNAME": "user"})
    env.update(kwargs.pop("env", {}))
    return subprocess.run(args, env=env, preexec_fn=as_user, **kwargs)


def expected_processor_lines():
    entries = []
    for name in os.listdir(TELEMETRY):
        path = os.path.join(TELEMETRY, name)
        st = os.stat(path, follow_symlinks=False)
        if stat.S_ISREG(st.st_mode):
            entries.append(
                (name, f"File: {name} | Size: {st.st_size} | Permissions: {stat.S_IMODE(st.st_mode):o}")
            )
    return [line for _, line in sorted(entries)]


def processor_output(path):
    result = run_user([path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"{path} failed: {result.stderr}"
    return result.stdout.splitlines()


def test_c_program_exists_executable_and_is_compiled_c():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."
    assert os.path.isfile(PROCESSOR), f"Executable {PROCESSOR} is missing."
    assert os.access(PROCESSOR, os.X_OK), f"Executable {PROCESSOR} is not executable."
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sensor_processor is not a compiled executable."


def test_sensor_processor_on_runtime_derived_directory_contents():
    token = uuid.uuid4().hex
    files = {
        f"zz_verifier_{token}_empty.dat": (b"", 0o604),
        f"zz_verifier_{token}_payload.dat": (os.urandom(137), 0o640),
    }
    directory = os.path.join(TELEMETRY, f"zz_verifier_{token}_directory")
    compiled = os.path.join("/tmp", f"sensor_processor_{token}")
    created = []
    try:
        for name, (content, mode) in files.items():
            path = os.path.join(TELEMETRY, name)
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, mode)
            os.chown(path, USER.pw_uid, USER.pw_gid)
            created.append(path)
        os.mkdir(directory)
        os.chown(directory, USER.pw_uid, USER.pw_gid)

        expected = expected_processor_lines()
        actual = processor_output(PROCESSOR)
        assert actual == expected, f"Unexpected processor output:\n{actual}\nExpected:\n{expected}"

        # Preserve the original fixed assertions as well.
        assert "File: sensor_a.dat | Size: 17 | Permissions: 644" in actual
        assert "File: sensor_b.dat | Size: 11 | Permissions: 600" in actual
        assert actual[0].startswith("File: sensor_a.dat")
        assert actual[1].startswith("File: sensor_b.dat")

        build = run_user(
            ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", compiled],
            capture_output=True, text=True, timeout=20
        )
        assert build.returncode == 0, f"C source does not compile: {build.stderr}"
        assert processor_output(compiled) == expected, "The submitted C source does not implement the aggregator."
    finally:
        if os.path.exists(compiled):
            os.unlink(compiled)
        if os.path.isdir(directory):
            os.rmdir(directory)
        for path in created:
            if os.path.exists(path):
                os.unlink(path)


def test_git_repo_initialized():
    assert os.path.isdir(f"{REPO}/.git"), "Git repository not initialized in /home/user/iot_sync_repo."
    result = run_user(["git", "-C", REPO, "rev-parse", "--is-inside-work-tree"], capture_output=True, text=True)
    assert result.returncode == 0 and result.stdout.strip() == "true"


def test_pre_commit_hook_exists_uses_required_tools_and_validates_message():
    assert os.path.isfile(HOOK), f"Pre-commit hook {HOOK} does not exist."
    assert os.access(HOOK, os.X_OK), f"Pre-commit hook {HOOK} is not executable."
    source = open(HOOK, encoding="utf-8").read()
    assert re.match(r"^#!.*(?:/|\b)bash(?:\s|$)", source.splitlines()[0]), "Hook must use bash."
    active = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    assert re.search(r"(^|[^A-Za-z0-9_])awk([^A-Za-z0-9_]|$)", active), "Hook must use awk."
    assert re.search(r"(^|[^A-Za-z0-9_])grep([^A-Za-z0-9_]|$)", active), "Hook must use grep."

    message_file = f"{REPO}/.git/COMMIT_EDITMSG"
    old = open(message_file, "rb").read() if os.path.exists(message_file) else None
    try:
        valid_messages = [
            REQUIRED + "\n",
            "Subject\n\n" + REQUIRED + "\nAdditional text\n",
        ]
        invalid_messages = [
            "Automated telemetry update.\n",
            "[IoT-Sync] Locale: en_US.UTF-8, Timezone: Europe/London\n",
            "[IoT-Sync] Locale: en_US.UTF-8 Timezone: UTC\n",
        ]
        for message in valid_messages:
            with open(message_file, "w", encoding="utf-8") as f:
                f.write(message)
            result = run_user([HOOK], cwd=REPO, capture_output=True, text=True, timeout=10)
            assert result.returncode == 0, f"Hook rejected a valid message: {result.stderr}"
        for message in invalid_messages:
            with open(message_file, "w", encoding="utf-8") as f:
                f.write(message)
            result = run_user([HOOK], cwd=REPO, capture_output=True, text=True, timeout=10)
            assert result.returncode != 0, f"Hook accepted invalid message: {message!r}"
    finally:
        if old is None:
            if os.path.exists(message_file):
                os.unlink(message_file)
        else:
            with open(message_file, "wb") as f:
                f.write(old)
            os.chown(message_file, USER.pw_uid, USER.pw_gid)


def test_sync_script_exists_and_declares_required_environment():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    source = open(SCRIPT, encoding="utf-8").read()
    assert re.match(r"^#!.*(?:/|\b)bash(?:\s|$)", source.splitlines()[0]), "Automation script must use bash."
    active = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    assert re.search(r"(?m)^\s*export\s+TZ\s*=\s*(['\"]?)UTC\1(?:\s|$)", active), "Script must explicitly export TZ=UTC."
    assert re.search(r"(?m)^\s*export\s+LC_ALL\s*=\s*(['\"]?)en_US\.UTF-8\1(?:\s|$)", active), "Script must explicitly export LC_ALL=en_US.UTF-8."


def test_existing_report_and_commit_assertions():
    assert os.path.isfile(REPORT), f"Report file {REPORT} does not exist."
    assert stat.S_IMODE(os.stat(REPORT).st_mode) == 0o400, f"Permissions for {REPORT} should be 400."
    result = run_user(["git", "-C", REPO, "log", "-1", "--pretty=%B"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to get git log. Is there a commit?"
    assert REQUIRED in result.stdout.strip(), f"Commit message does not contain the required string: {result.stdout}"


def test_automation_generates_secures_stages_and_commits_report():
    token = uuid.uuid4().hex
    dynamic_file = os.path.join(TELEMETRY, f"zz_sync_verifier_{token}.dat")
    backup = os.path.join(HOME, f".sensor_processor_verifier_{token}")
    env_capture = os.path.join("/tmp", f"sync_env_{token}")
    with open(dynamic_file, "wb") as f:
        f.write(os.urandom(211))
    os.chmod(dynamic_file, 0o620)
    os.chown(dynamic_file, USER.pw_uid, USER.pw_gid)
    expected = expected_processor_lines()
    old_head = run_user(["git", "-C", REPO, "rev-parse", "HEAD"], capture_output=True, text=True)
    assert old_head.returncode == 0

    if os.path.exists(REPORT):
        os.unlink(REPORT)
    os.replace(PROCESSOR, backup)
    wrapper = f"#!/bin/bash\nprintf '%s\\n%s\\n' \"$TZ\" \"$LC_ALL\" > {env_capture}\nexec {backup} \"$@\"\n"
    with open(PROCESSOR, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(PROCESSOR, 0o755)
    os.chown(PROCESSOR, USER.pw_uid, USER.pw_gid)

    try:
        result = run_user([SCRIPT], cwd=HOME, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Automation script failed: stdout={result.stdout!r} stderr={result.stderr!r}"
        assert os.path.isfile(env_capture), "Automation script did not run /home/user/sensor_processor."
        assert open(env_capture, encoding="utf-8").read().splitlines() == ["UTC", "en_US.UTF-8"]
        assert os.path.isfile(REPORT), "Automation script did not generate telemetry_report.txt."
        assert open(REPORT, encoding="utf-8").read().splitlines() == expected, "Generated report is not processor output."
        assert stat.S_IMODE(os.stat(REPORT).st_mode) == 0o400, "Generated report permissions are not 0400."

        new_head = run_user(["git", "-C", REPO, "rev-parse", "HEAD"], capture_output=True, text=True)
        assert new_head.returncode == 0 and new_head.stdout.strip() != old_head.stdout.strip(), "Script did not create a new commit."
        message = run_user(["git", "-C", REPO, "log", "-1", "--pretty=%B"], capture_output=True, text=True)
        assert message.returncode == 0
        assert message.stdout.strip().splitlines() == [REQUIRED, "Automated telemetry update."], "Commit message is incorrect."
        tracked = run_user(["git", "-C", REPO, "ls-tree", "--name-only", "HEAD", "--", "telemetry_report.txt"], capture_output=True, text=True)
        assert tracked.stdout.strip() == "telemetry_report.txt", "Report was not staged and committed."
        committed = run_user(["git", "-C", REPO, "show", "HEAD:telemetry_report.txt"], capture_output=True, text=True)
        assert committed.returncode == 0 and committed.stdout.splitlines() == expected, "Committed report differs from generated report."
        status = run_user(["git", "-C", REPO, "status", "--porcelain", "--", "telemetry_report.txt"], capture_output=True, text=True)
        assert status.stdout.strip() == "", "telemetry_report.txt remains unstaged or uncommitted."
    finally:
        if os.path.exists(PROCESSOR):
            os.unlink(PROCESSOR)
        if os.path.exists(backup):
            os.replace(backup, PROCESSOR)
        if os.path.exists(env_capture):
            os.unlink(env_capture)
        if os.path.exists(dynamic_file):
            os.unlink(dynamic_file)


def test_user_crontab_has_active_exact_five_minute_entry():
    result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read user's crontab."
    content = result.stdout.strip()
    # Preserve the original assertions while additionally requiring one active, valid entry.
    assert SCRIPT in content, "Crontab does not contain the sync script."
    assert "*/5 * * * *" in content or "0,5,10,15,20,25,30,35,40,45,50,55 * * * *" in content
    valid_minutes = {"*/5", "0,5,10,15,20,25,30,35,40,45,50,55"}
    found = False
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" in line.split()[0]:
            continue
        fields = line.split(None, 5)
        if len(fields) != 6:
            continue
        minute, hour, dom, month, dow, command = fields
        if minute in valid_minutes and [hour, dom, month, dow] == ["*", "*", "*", "*"]:
            if re.match(r"^/home/user/sync_telemetry\.sh(?:\s|$)", command):
                found = True
                break
    assert found, "No active crontab entry runs the sync script exactly every five minutes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
