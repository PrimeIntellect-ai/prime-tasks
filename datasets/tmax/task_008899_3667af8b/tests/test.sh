#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shlex
import signal
import subprocess
import tempfile


def run_monitor(payload):
    path = "/home/user/monitor.sh"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    assert os.access(path, os.X_OK), f"Expected file {path} to be executable."
    return subprocess.run([path, payload], capture_output=True, text=True, timeout=5)


def assert_monitor_result(decoded, expected):
    encoded = base64.b64encode(decoded).decode("ascii")
    result = run_monitor(encoded)
    assert result.returncode == 0, (
        f"monitor.sh failed with exit code {result.returncode} for decoded input {decoded!r}."
    )
    assert result.stderr == "", (
        f"monitor.sh produced error output for decoded input {decoded!r}: {result.stderr!r}"
    )
    assert result.stdout == expected + "\n", (
        f"monitor.sh returned {result.stdout!r} for decoded input {decoded!r}; expected {expected!r}."
    )


def test_crash_payload_txt():
    path = "/home/user/crash_payload.txt"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "UP AND RUNNING" in content, "crash_payload.txt does not contain the correct decoded payload that caused the crash."
    with open(path, "rb") as f:
        raw = f.read()
    assert raw == b"UP AND RUNNING\n", (
        "crash_payload.txt must contain the exact decoded crashing payload, including its trailing newline."
    )


def test_fuzzer_sh_exists_and_executable():
    path = "/home/user/fuzzer.sh"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    assert os.access(path, os.X_OK), f"Expected file {path} to be executable."


def test_fuzzer_executes_at_least_ten_distinct_cases():
    fuzzer = "/home/user/fuzzer.sh"
    monitor = "/home/user/monitor.sh"
    assert os.path.isfile(fuzzer), f"Expected file {fuzzer} does not exist."
    assert os.access(fuzzer, os.X_OK), f"Expected file {fuzzer} to be executable."
    assert os.path.isfile(monitor), f"Expected file {monitor} does not exist."

    with open(monitor, "rb") as f:
        original_data = f.read()
    original_mode = os.stat(monitor).st_mode

    with tempfile.TemporaryDirectory(prefix="fuzzer-check-") as td:
        real_monitor = os.path.join(td, "real-monitor.sh")
        call_log = os.path.join(td, "calls.bin")
        with open(real_monitor, "wb") as f:
            f.write(original_data)
        os.chmod(real_monitor, original_mode)

        wrapper = (
            "#!/bin/bash\n"
            f"printf '%s\\0' \"$1\" >> {shlex.quote(call_log)}\n"
            f"exec {shlex.quote(real_monitor)} \"$@\"\n"
        )

        proc = None
        try:
            with open(monitor, "w") as f:
                f.write(wrapper)
            os.chmod(monitor, 0o755)

            proc = subprocess.Popen(
                [fuzzer],
                cwd="/home/user",
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            try:
                proc.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                raise AssertionError("fuzzer.sh did not finish within 20 seconds.")

            logged = b""
            if os.path.exists(call_log):
                with open(call_log, "rb") as f:
                    logged = f.read()
            calls = logged.split(b"\0")
            if calls and calls[-1] == b"":
                calls.pop()

            assert len(calls) >= 10, (
                f"fuzzer.sh called ./monitor.sh only {len(calls)} times; at least 10 cases are required."
            )
            assert len(set(calls)) >= 10, (
                f"fuzzer.sh supplied only {len(set(calls))} distinct payloads; at least 10 different cases are required."
            )
        finally:
            if proc is not None and proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            with open(monitor, "wb") as f:
                f.write(original_data)
            os.chmod(monitor, original_mode)


def test_monitor_sh_fixed_malicious_payload():
    path = "/home/user/monitor.sh"
    result = subprocess.run([path, "VVAgQU5EIFJVTk5JTkcK"], capture_output=True, text=True)
    assert result.returncode == 0, f"monitor.sh failed with exit code {result.returncode} on malicious payload."
    assert result.stderr.strip() == "", f"monitor.sh produced error output on malicious payload: {result.stderr}"
    assert "Service is DOWN" in result.stdout, "monitor.sh did not output 'Service is DOWN' for the malicious payload."


def test_monitor_sh_valid_payload():
    path = "/home/user/monitor.sh"
    result = subprocess.run([path, "VVA="], capture_output=True, text=True)
    assert result.returncode == 0, f"monitor.sh failed with exit code {result.returncode} on valid payload."
    assert result.stderr.strip() == "", f"monitor.sh produced error output on valid payload: {result.stderr}"
    assert "Service is UP" in result.stdout, "monitor.sh did not output 'Service is UP' for the 'UP' payload."


def test_monitor_handles_edge_cases_and_unpredictable_payloads():
    edge_cases = [
        b"",
        b" ",
        b"UP ",
        b" UP",
        b"UP\n",
        b"UP\n\n",
        b"DOWN",
        b"UP AND RUNNING\n",
        b"a b c",
        b"* ? [ ]",
        b"!",
        b"-n",
        b"=",
        b"$(echo UP)",
        b"`echo UP`",
        b"\"UP\"",
        b"UP; exit 1",
        b"line one\nline two",
        b"\tUP\t",
    ]

    random_cases = []
    for _ in range(25):
        length = 1 + secrets.randbelow(80)
        data = bytes((1 + secrets.randbelow(255)) for _ in range(length))
        if data == b"UP":
            data += b"x"
        random_cases.append(data)

    assert_monitor_result(b"UP", "Service is UP")
    for decoded in edge_cases + random_cases:
        assert_monitor_result(decoded, "Service is DOWN")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
