#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shlex
import shutil
import subprocess
import tempfile
import time

APP = "/app/log-alerter"
LOG = "/app/large_access.log"
SUMMARY = "/home/user/alerts/summary.log"
EMAILS = "/home/user/emails.log"
CANDIDATES = [
    "/app/log-alerter/target/release/log-alerter",
    "/app/log-alerter/target/debug/log-alerter",
]


def get_expected_count():
    count = 0
    with open(LOG, "r") as f:
        for line in f:
            if "CRITICAL_ERROR" in line:
                count += 1
    return count


def port_2525_is_listening():
    wanted = format(2525, "04X")
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 4 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        return True
        except FileNotFoundError:
            pass
    return False


def wait_for_email(text, timeout=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(EMAILS):
            with open(EMAILS, "r", errors="replace") as f:
                if text in f.read():
                    return True
        time.sleep(0.05)
    return False


def built_elfs():
    result = []
    for path in CANDIDATES:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            with open(path, "rb") as f:
                if f.read(4) == b"\x7fELF":
                    result.append(path)
    return result


def test_rust_package_builds_and_binary_exists():
    assert os.path.isfile(os.path.join(APP, "Cargo.toml")), "Cargo.toml is missing"
    assert os.path.isfile(os.path.join(APP, "src/main.rs")), "Rust source is missing"
    result = subprocess.run(["make"], cwd=APP, capture_output=True, timeout=120)
    assert result.returncode == 0, (
        "make failed\nstdout:\n" + result.stdout.decode(errors="replace") +
        "\nstderr:\n" + result.stderr.decode(errors="replace")
    )
    assert built_elfs(), "make did not produce an executable ELF log-alerter binary"


def test_execution_time_and_output():
    assert port_2525_is_listening(), "No background SMTP server is listening on port 2525"

    # Remove existing files to ensure we test the current run
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)
    with open(EMAILS, "w"):
        pass

    expected_count = get_expected_count()

    start_time = time.time()
    result = subprocess.run(["env", "-i", "bash", "/home/user/monitor.sh"], capture_output=True)
    end_time = time.time()

    execution_time = end_time - start_time

    # Check execution time
    assert execution_time <= 1.5, f"Execution time {execution_time:.2f}s exceeded threshold of 1.5s"

    # Check script execution success
    assert result.returncode == 0, f"monitor.sh failed with return code {result.returncode}\nStderr: {result.stderr.decode()}"

    # Check summary.log exists
    assert os.path.exists(SUMMARY), f"{SUMMARY} was not created"

    # Check summary.log content
    with open(SUMMARY, "r") as f:
        content = f.read().strip()

    expected_content = f"Found {expected_count} critical errors"
    assert expected_content in content, f"Expected '{expected_content}' in summary.log, found '{content}'"


def test_email_sent():
    assert os.path.exists(EMAILS), f"{EMAILS} does not exist. Is the SMTP server running and saving to this file?"

    expected_count = get_expected_count()
    expected_email_content = f"Found {expected_count} errors"

    assert wait_for_email(expected_email_content), (
        f"Expected '{expected_email_content}' in {EMAILS}, but it was not found."
    )
    assert port_2525_is_listening(), "SMTP server stopped listening on port 2525"


def test_monitor_invokes_built_artifact_and_artifact_behaves():
    binaries = built_elfs()
    assert binaries, "No built ELF artifact is available"

    controlled_count = 17 + int.from_bytes(os.urandom(1), "big") % 31
    backup_fd, backup_path = tempfile.mkstemp(prefix="large_access.", dir="/tmp")
    os.close(backup_fd)
    shutil.copy2(LOG, backup_path)

    token = tempfile.mktemp(prefix="log-alerter-executed.", dir="/tmp")
    moved = {}
    try:
        with open(LOG, "w") as f:
            for i in range(160):
                suffix = " CRITICAL_ERROR" if i < controlled_count else ""
                f.write(f"controlled request {i}{suffix}\n")

        # Interpose a tiny shim at every valid artifact path. It records execution
        # and immediately execs the original ELF, preserving its real behavior.
        for path in binaries:
            real = path + ".verifier-real"
            assert not os.path.exists(real), f"Unexpected verifier backup path exists: {real}"
            os.rename(path, real)
            moved[path] = real
            with open(path, "w") as f:
                f.write("#!/bin/bash\n")
                f.write("printf '%s\\n' " + shlex.quote(path) + " >> " + shlex.quote(token) + "\n")
                f.write("exec " + shlex.quote(real) + " \"$@\"\n")
            os.chmod(path, 0o755)

        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)
        with open(EMAILS, "w"):
            pass

        result = subprocess.run(["env", "-i", "bash", "/home/user/monitor.sh"], capture_output=True, timeout=5)
        assert result.returncode == 0, (
            f"monitor.sh failed during artifact execution check: {result.stderr.decode(errors='replace')}"
        )
        assert os.path.exists(token), "monitor.sh did not execute either built log-alerter artifact"
        with open(token, "r") as f:
            invoked = [line.strip() for line in f if line.strip()]
        assert any(path in invoked for path in binaries), "monitor.sh did not invoke a verified ELF artifact"

        expected_summary = f"Found {controlled_count} critical errors"
        assert os.path.exists(SUMMARY), "Built artifact did not create summary.log"
        with open(SUMMARY, "r") as f:
            content = f.read().strip()
        assert expected_summary in content, f"Expected '{expected_summary}', found '{content}'"
        assert wait_for_email(f"Found {controlled_count} errors"), "Built artifact did not send the derived alert email"
    finally:
        for path, real in moved.items():
            if os.path.lexists(path):
                os.remove(path)
            if os.path.exists(real):
                os.rename(real, path)
        if os.path.exists(backup_path):
            os.replace(backup_path, LOG)
        if os.path.exists(token):
            os.remove(token)

    # Execute the artifact selected by monitor.sh directly after restoring it,
    # proving that the artifact itself, rather than the shim, implements the work.
    selected = next((path for path in invoked if path in binaries), None)
    assert selected and os.path.isfile(selected)
    shutil.copy2(LOG, backup_path)
    try:
        with open(LOG, "w") as f:
            for i in range(100):
                f.write(("CRITICAL_ERROR" if i < controlled_count else "ordinary") + "\n")
        if os.path.exists(SUMMARY):
            os.remove(SUMMARY)
        start = time.time()
        result = subprocess.run(
            [selected], cwd=APP,
            env={"ALERT_DIR": "/home/user/alerts"},
            capture_output=True, timeout=5
        )
        elapsed = time.time() - start
        assert result.returncode == 0, f"Built artifact failed when executed directly: {result.stderr.decode(errors='replace')}"
        assert elapsed <= 1.5, f"Built artifact took {elapsed:.2f}s on controlled input"
        with open(SUMMARY, "r") as f:
            content = f.read().strip()
        assert f"Found {controlled_count} critical errors" in content
    finally:
        if os.path.exists(backup_path):
            os.replace(backup_path, LOG)

    assert port_2525_is_listening(), "SMTP server is not still running on port 2525"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
