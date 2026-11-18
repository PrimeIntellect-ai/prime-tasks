#!/bin/bash
set -e
mkdir -p /logs/verifier

# Prevent the setup's git wrapper from starting the billing service during the
# controlled UP/DOWN tests. Restore it when verification finishes.
GIT_WRAPPER_BACKUP="/tmp/git-wrapper-verifier.$$"
mv /usr/bin/git "$GIT_WRAPPER_BACKUP"
ln -s /usr/bin/git-real /usr/bin/git
cleanup() {
    rm -f /usr/bin/git
    mv "$GIT_WRAPPER_BACKUP" /usr/bin/git
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import signal
import socket
import subprocess
import threading
import time
from pathlib import Path
from zoneinfo import ZoneInfo

SRC = Path("/home/user/hook.cpp")
REPO = Path("/home/user/finops-repo")
HOOK = REPO / ".git/hooks/post-commit"
LOG = Path("/home/user/cost_health.log")
LINE_RE = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) JST\] "
    r"COMMIT: ([a-f0-9]{40}) - BILLING_SVC: (UP|DOWN)$"
)


def git_head():
    result = subprocess.run(
        ["/usr/bin/git-real", "rev-parse", "HEAD"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def read_lines():
    return LOG.read_text().splitlines() if LOG.exists() else []


def parse_and_validate(line, expected_hash, expected_state):
    match = LINE_RE.fullmatch(line)
    assert match is not None, f"Log line format is incorrect. Found: '{line}'"
    assert match.group(2) == expected_hash, (
        f"Commit hash in log ({match.group(2)}) does not match {expected_hash}."
    )
    assert match.group(3) == expected_state, (
        f"Expected BILLING_SVC to be {expected_state}, but found {match.group(3)}."
    )
    logged = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").replace(
        tzinfo=ZoneInfo("Asia/Tokyo")
    )
    now = datetime.datetime.now(ZoneInfo("Asia/Tokyo"))
    assert abs((now - logged).total_seconds()) <= 120, (
        f"Timestamp is not current Asia/Tokyo time: {match.group(1)} JST"
    )


def kill_http_service():
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmd = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="ignore")
            if "http.server" in cmd and "10080" in cmd:
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)


def assert_port_closed():
    for _ in range(20):
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.settimeout(0.1)
        result = probe.connect_ex(("127.0.0.1", 10080))
        probe.close()
        if result != 0:
            return
        time.sleep(0.1)
    assert False, "Port 10080 remained open when testing the DOWN state"


class ControlledService:
    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 10080))
        self.sock.listen(5)
        self.sock.settimeout(8)
        self.accepted = threading.Event()
        self.error = None
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def _serve(self):
        try:
            conn, _ = self.sock.accept()
            self.accepted.set()
            conn.close()
        except Exception as exc:
            self.error = exc

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        self.sock.close()
        self.thread.join(timeout=1)


def run_direct(binary, expected_state, with_service):
    before = read_lines()
    env = os.environ.copy()
    env["TZ"] = "UTC"
    expected_hash = git_head()

    if with_service:
        with ControlledService() as service:
            result = subprocess.run(
                [str(binary)], cwd=REPO, env=env, capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0, result.stderr
            assert service.accepted.wait(2), "The program did not connect to 127.0.0.1:10080"
    else:
        assert_port_closed()
        result = subprocess.run(
            [str(binary)], cwd=REPO, env=env, capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, result.stderr

    after = read_lines()
    assert len(after) == len(before) + 1, "Each execution must append exactly one log line"
    parse_and_validate(after[-1], expected_hash, expected_state)


# Original verifier assertions are retained.
def test_source_code_exists():
    assert SRC.is_file(), f"C++ source code file not found at {SRC}."


def test_hook_executable():
    assert HOOK.is_file(), f"Git hook not found at {HOOK}."
    assert os.access(HOOK, os.X_OK), f"Git hook at {HOOK} is not executable."


def test_log_file_exists():
    assert LOG.is_file(), f"Log file not found at {LOG}."


def test_log_content_and_format():
    latest_commit = git_head()
    assert len(latest_commit) == 40, "Invalid commit hash retrieved."
    lines = read_lines()
    assert len(lines) > 0, f"Log file {LOG} is empty."
    match = LINE_RE.fullmatch(lines[-1])
    assert match is not None, f"Log line format is incorrect. Found: '{lines[-1]}'"
    assert match.group(2) == latest_commit, (
        f"Commit hash in log ({match.group(2)}) does not match the latest commit ({latest_commit})."
    )
    assert match.group(3) == "UP", (
        f"Expected BILLING_SVC to be UP, but found {match.group(3)}."
    )


def test_source_and_installed_hook_behaviour():
    source = SRC.read_text(errors="replace")
    assert "Asia/Tokyo" in source, "Source does not configure the Asia/Tokyo timezone"
    assert re.search(r"\b(setenv|putenv|tzset|locate_zone|zoned_time)\b", source), (
        "Source does not contain a programmatic timezone configuration"
    )

    # The installed artifact must be a compiled native executable, not a script.
    assert HOOK.read_bytes()[:4] == b"\x7fELF", "post-commit is not a compiled ELF executable"

    rebuilt = Path("/tmp/rebuilt-finops-hook")
    compile_result = subprocess.run(
        ["/usr/bin/g++-real", str(SRC), "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"hook.cpp does not compile:\n{compile_result.stderr}"

    kill_http_service()

    # Exercise the submitted source against a listener controlled by the verifier,
    # then with no listener to validate both health-check outcomes.
    run_direct(rebuilt, "UP", True)
    run_direct(rebuilt, "DOWN", False)

    # Exercise the installed hook through an actual new commit. The expected hash
    # is derived only after Git creates that commit.
    before = read_lines()
    with ControlledService() as service:
        result = subprocess.run(
            ["/usr/bin/git-real", "commit", "--allow-empty", "-m", "Verifier hook exercise"],
            cwd=REPO,
            env={**os.environ, "TZ": "UTC"},
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Commit/hook execution failed:\n{result.stderr}"
        assert service.accepted.wait(2), "Installed post-commit hook made no TCP connection"

    after = read_lines()
    assert len(after) == len(before) + 1, "The installed hook must append exactly one line per commit"
    parse_and_validate(after[-1], git_head(), "UP")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
