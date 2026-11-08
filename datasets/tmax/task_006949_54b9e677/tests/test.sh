#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import secrets
import shutil
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

ORIGINAL = "/home/user/legacy_app.log"
BACKUP = "/home/user/backup/legacy_app.log.bak"
SOURCE = "/home/user/exporter.rs"
BINARY = "/home/user/exporter"
SCRIPT = "/home/user/run_exporter.sh"
METRICS = "/home/user/metrics/metrics.txt"


def expected_metrics(lines):
    errors = sum("[ERROR]" in line for line in lines)
    warnings = sum("[WARN]" in line for line in lines)
    return f"""# HELP legacy_app_errors Total errors
# TYPE legacy_app_errors counter
legacy_app_errors {errors}
# HELP legacy_app_warnings Total warnings
# TYPE legacy_app_warnings counter
legacy_app_warnings {warnings}"""


def read_metrics():
    assert os.path.isfile(METRICS), f"Metrics file {METRICS} does not exist."
    with open(METRICS, "r", encoding="utf-8") as f:
        return f.read().strip()


def write_log(lines):
    with open(ORIGINAL, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def stop_port_9090():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for row in f:
                    fields = row.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port == 9090:
                            inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass

    deadline = time.time() + 3
    while time.time() < deadline:
        with socket.socket() as s:
            if s.connect_ex(("127.0.0.1", 9090)) != 0:
                return
        time.sleep(0.1)
    assert False, "Could not stop the existing listener on port 9090."


def test_backup_file_exists_and_matches():
    assert os.path.isfile(BACKUP), f"Backup file {BACKUP} does not exist."
    assert filecmp.cmp(ORIGINAL, BACKUP, shallow=False), f"Backup file {BACKUP} does not match the original {ORIGINAL}."


def test_rust_source_exists():
    assert os.path.isfile(SOURCE), f"Rust source file {SOURCE} does not exist."


def test_rust_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Rust binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Rust binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Binary {BINARY} is not a compiled executable."


def test_run_exporter_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Automation script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Automation script {SCRIPT} is not executable."


def test_metrics_file_content():
    expected_content = """# HELP legacy_app_errors Total errors
# TYPE legacy_app_errors counter
legacy_app_errors 3
# HELP legacy_app_warnings Total warnings
# TYPE legacy_app_warnings counter
legacy_app_warnings 2"""
    content = read_metrics()
    assert content == expected_content, f"Metrics file content does not match the expected Prometheus format.\nExpected:\n{expected_content}\nGot:\n{content}"


def test_http_server_running_and_serving_metrics():
    url = "http://127.0.0.1:9090/metrics.txt"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP status 200, got {response.status}."
            content = response.read().decode("utf-8").strip()
    except urllib.error.URLError as e:
        assert False, f"Failed to reach the HTTP server at {url}. Is it running? Error: {e}"

    expected_content = """# HELP legacy_app_errors Total errors
# TYPE legacy_app_errors counter
legacy_app_errors 3
# HELP legacy_app_warnings Total warnings
# TYPE legacy_app_warnings counter
legacy_app_warnings 2"""
    assert content == expected_content, "HTTP server is not serving the correct metrics.txt content."


def test_exporter_and_automation_on_changed_input():
    with open(ORIGINAL, "rb") as f:
        original_bytes = f.read()

    compiled_source = "/tmp/exporter_compiled_from_submission"
    real_binary = "/tmp/submitted_exporter_real"
    marker = f"/tmp/exporter_invoked_{secrets.token_hex(8)}"

    try:
        compile_result = subprocess.run(
            ["rustc", SOURCE, "-o", compiled_source],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"exporter.rs failed to compile with rustc:\n{compile_result.stderr}"

        token = secrets.token_hex(12)
        cases = [
            [
                f"{token} plain line",
                "lowercase [error] must not count",
                "one [ERROR] line",
                "one [WARN] line",
                "both [ERROR] and [WARN] on one line",
                "two occurrences still one line [ERROR] [ERROR]",
            ],
            [
                f"{token} [WARN] alpha",
                "nothing here",
                "[WARNINGS] is not the exact substring",
                "prefix[ERROR]suffix",
                "[WARN] again",
                "[WARN] and [ERROR] together",
                "final [ERROR]",
            ],
        ]

        for executable in (BINARY, compiled_source):
            for lines in cases:
                write_log(lines)
                try:
                    os.remove(METRICS)
                except FileNotFoundError:
                    pass
                result = subprocess.run(
                    [executable],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                assert result.returncode == 0, f"{executable} failed on changed input:\n{result.stderr}"
                assert read_metrics() == expected_metrics(lines), f"{executable} did not derive correct counts from changed input."

        automation_lines = [
            f"automation-{token}",
            "[WARN] first warning",
            "[ERROR] first error",
            "[ERROR] and [WARN] combined",
            "[ERROR][ERROR] remains one error line",
            "case-sensitive [warn] does not count",
        ]
        write_log(automation_lines)
        expected = expected_metrics(automation_lines)
        try:
            os.remove(METRICS)
        except FileNotFoundError:
            pass

        stop_port_9090()
        shutil.move(BINARY, real_binary)
        with open(BINARY, "w", encoding="utf-8") as f:
            f.write(f"#!/bin/sh\nprintf invoked > {marker}\nexec {real_binary} \"$@\"\n")
        os.chmod(BINARY, 0o755)

        result = subprocess.run(
            [SCRIPT],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=8,
        )
        assert result.returncode == 0, "run_exporter.sh did not return successfully."

        deadline = time.time() + 8
        last_error = None
        served = None
        while time.time() < deadline:
            try:
                with urllib.request.urlopen("http://127.0.0.1:9090/metrics.txt", timeout=1) as response:
                    if response.status == 200:
                        served = response.read().decode("utf-8").strip()
                        break
            except (urllib.error.URLError, TimeoutError) as e:
                last_error = e
            time.sleep(0.2)

        assert os.path.isfile(marker), "run_exporter.sh did not execute /home/user/exporter."
        assert read_metrics() == expected, "run_exporter.sh did not regenerate metrics from the changed log."
        assert served is not None, f"run_exporter.sh did not start an HTTP server on port 9090: {last_error}"
        assert served == expected, "The HTTP server did not serve the dynamically generated metrics."
    finally:
        with open(ORIGINAL, "wb") as f:
            f.write(original_bytes)
        if os.path.exists(real_binary):
            try:
                os.remove(BINARY)
            except FileNotFoundError:
                pass
            shutil.move(real_binary, BINARY)
        for path in (compiled_source, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
