#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import shutil
import subprocess
import tempfile
import time
import uuid

SERVICE = "/home/user/app_service.sh"
SOURCE = "/home/user/monitor.rs"
BINARY = "/home/user/monitor_bin"
REPO = "/home/user/service.git"
HOOK = "/home/user/service.git/hooks/post-receive"
LOG = "/home/user/alert.log"

CRITICAL = "CRITICAL: Service was down. Restarted."
INFO = "INFO: Deployment pushed. Service is active."
LINE_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+0900)\] (CRITICAL: Service was down\. Restarted\.|INFO: Deployment pushed\. Service is active\.)$")


def is_executable(path):
    return os.path.isfile(path) and os.access(path, os.X_OK)


def kill_service():
    subprocess.run(["pkill", "-f", "/home/user/app_service.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)


def service_pids():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            with open(f"/proc/{name}/stat", "r") as f:
                state = f.read().split()[2]
        except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError):
            continue
        if SERVICE in args and state != "Z":
            found.append(int(name))
    return found


def read_lines():
    if not os.path.exists(LOG):
        return []
    with open(LOG, "r") as f:
        return f.read().splitlines()


def run_and_check(binary, expected):
    before = read_lines()
    started = time.time()
    result = subprocess.run([binary], capture_output=True, text=True, timeout=10)
    finished = time.time()
    assert result.returncode == 0, f"{binary} failed: {result.stderr}"

    after = read_lines()
    assert len(after) == len(before) + 1, "Each supervisor invocation must append exactly one alert line"
    assert after[:len(before)] == before, "Supervisor replaced or altered existing alert log entries"

    line = after[-1]
    match = LINE_RE.fullmatch(line)
    assert match, f"Malformed alert line: {line!r}"
    assert match.group(2) == expected, f"Expected {expected!r}, got {match.group(2)!r}"

    stamp = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S %z").timestamp()
    assert started - 2 <= stamp <= finished + 2, "Alert timestamp is not the current time"
    return line


def exercise_supervisor(binary):
    kill_service()
    if os.path.exists(LOG):
        os.remove(LOG)

    run_and_check(binary, CRITICAL)
    res = subprocess.run(["pgrep", "-f", "app_service.sh"], capture_output=True)
    assert res.returncode == 0, "app_service.sh is not running after the down-state invocation"
    assert service_pids(), "Supervisor did not start the actual /home/user/app_service.sh script"

    run_and_check(binary, INFO)

    # Re-test the down state after an active-state invocation, so behavior cannot
    # be faked by alternating messages or consulting only the log.
    kill_service()
    run_and_check(binary, CRITICAL)
    assert service_pids(), "Supervisor did not restart the actual service"

    # Test an initially-active service with an empty log.
    kill_service()
    if os.path.exists(LOG):
        os.remove(LOG)
    subprocess.Popen([SERVICE], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    deadline = time.time() + 3
    while time.time() < deadline and not service_pids():
        time.sleep(0.05)
    assert service_pids(), "Test could not start the target service"
    run_and_check(binary, INFO)
    kill_service()


def test_files_and_permissions():
    assert is_executable(SERVICE), "/home/user/app_service.sh is missing or not executable"
    assert is_executable(BINARY), "/home/user/monitor_bin is missing or not executable"
    assert is_executable(HOOK), "/home/user/service.git/hooks/post-receive is missing or not executable"
    assert os.path.isfile(SOURCE), "/home/user/monitor.rs is missing"

    with open(SERVICE, "rb") as f:
        assert f.read() == b"#!/bin/bash\nwhile true; do sleep 60; done\n", "app_service.sh does not have the required content"

    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "monitor_bin is not a compiled Linux executable"

    assert os.path.isdir(os.path.join(REPO, "objects")), "/home/user/service.git is not a valid git repository"
    bare = subprocess.run(["git", "-C", REPO, "rev-parse", "--is-bare-repository"], check=True, capture_output=True, text=True)
    assert bare.stdout.strip() == "true", "/home/user/service.git is not bare"

    with open(HOOK, "r") as f:
        commands = [line.strip() for line in f if line.strip() and not line.lstrip().startswith("#")]
    assert commands in [[BINARY], ["exec " + BINARY]], "post-receive must simply execute /home/user/monitor_bin"


def test_compiled_binary_behavior():
    exercise_supervisor(BINARY)


def test_rust_source_compiles_and_implements_supervisor():
    build_dir = tempfile.mkdtemp()
    try:
        rebuilt = os.path.join(build_dir, "monitor_from_source")
        result = subprocess.run(["rustc", SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, f"monitor.rs does not compile with rustc: {result.stderr}"
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        exercise_supervisor(rebuilt)
    finally:
        kill_service()
        shutil.rmtree(build_dir)


def test_git_hook_and_supervisor_behavior():
    # 1. Kill any running instances to ensure a clean state
    kill_service()

    # Remove log if exists
    if os.path.exists(LOG):
        os.remove(LOG)

    # Create a temp clone
    temp_dir = tempfile.mkdtemp()
    try:
        # Clone the bare repo
        subprocess.run(["git", "clone", REPO, temp_dir], check=True, capture_output=True)

        token = uuid.uuid4().hex

        # First push (Service down)
        first_name = f"trigger-{token}-1.txt"
        with open(os.path.join(temp_dir, first_name), "w") as f:
            f.write("trigger1\n")

        subprocess.run(["git", "add", first_name], cwd=temp_dir, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "1"], cwd=temp_dir, check=True, capture_output=True)
        subprocess.run(["git", "push", "origin", "HEAD:master"], cwd=temp_dir, check=True, capture_output=True)
        time.sleep(1)

        assert os.path.exists(LOG), "/home/user/alert.log was not created after the first push"
        with open(LOG, "r") as f:
            log_content1 = f.read()

        assert CRITICAL in log_content1, "CRITICAL message not found in log after first push"
        assert "+0900]" in log_content1, "Timezone +0900 (Asia/Tokyo) not found in log timestamp"
        lines1 = log_content1.splitlines()
        assert len(lines1) == 1 and LINE_RE.fullmatch(lines1[0]), "First push did not produce exactly one valid alert"
        assert lines1[0].endswith(CRITICAL), "First push did not report the down state"

        # Check if service is started
        res = subprocess.run(["pgrep", "-f", "app_service.sh"], capture_output=True)
        assert res.returncode == 0, "app_service.sh is not running after the first push"
        assert service_pids(), "The hook did not start the actual target service"

        # Second push (Service active)
        second_name = f"trigger-{token}-2.txt"
        with open(os.path.join(temp_dir, second_name), "w") as f:
            f.write("trigger2\n")

        subprocess.run(["git", "add", second_name], cwd=temp_dir, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "2"], cwd=temp_dir, check=True, capture_output=True)
        subprocess.run(["git", "push", "origin", "HEAD:master"], cwd=temp_dir, check=True, capture_output=True)
        time.sleep(1)

        with open(LOG, "r") as f:
            log_content2 = f.read()

        assert INFO in log_content2, "INFO message not found in log after second push"
        lines2 = log_content2.splitlines()
        assert len(lines2) == 2 and LINE_RE.fullmatch(lines2[1]), "Second push did not append exactly one valid alert"
        assert lines2[1].endswith(INFO), "Second push did not report the active state"

    finally:
        shutil.rmtree(temp_dir)
        kill_service()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
