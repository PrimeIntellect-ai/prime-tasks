#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_daemon.py
import json
import math
import os
import random
import signal
import stat
import string
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:8080"
PROJECT = Path("/app/analytics-daemon-1.2.3")
RNG = random.SystemRandom()


def request(method, path, headers=None, timeout=2):
    req = urllib.request.Request(BASE + path, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def stats():
    status, body = request("GET", "/stats")
    assert status == 200, f"Failed to get stats, status: {status}"
    try:
        data = json.loads(body)
    except (ValueError, TypeError) as exc:
        raise AssertionError("Daemon did not return valid JSON") from exc
    assert "average" in data, "Response missing 'average' key"
    assert "count" in data, "Response missing 'count' key"
    assert isinstance(data["count"], int) and not isinstance(data["count"], bool)
    assert isinstance(data["average"], (int, float)) and not isinstance(data["average"], bool)
    assert math.isfinite(float(data["average"]))
    return float(data["average"]), data["count"]


def assert_close(actual, expected):
    tolerance = max(1e-9, abs(expected) * 1e-10)
    assert abs(actual - expected) <= tolerance, f"Expected average {expected}, got {actual}"


def original_assertions():
    initial_average, initial_count = stats()
    initial_sum = initial_count * initial_average

    status, _ = request("POST", "/submit?value=10")
    assert status == 200, f"First POST failed, status: {status}"

    status, _ = request(
        "POST", "/submit?value=5", {"X-Internal-Debug": "admin"}
    )
    assert status == 200, f"Second POST failed, status: {status}"

    final_average, final_count = stats()
    expected_count = initial_count + 2
    expected_average = (initial_sum + 10 + 5) / expected_count
    assert final_count == expected_count, f"Expected count {expected_count}, got {final_count}"
    assert_close(final_average, expected_average)


def random_token(prefix):
    return prefix + "".join(RNG.choice(string.ascii_letters) for _ in range(14))


def randomized_assertions(rounds=16):
    initial_average, initial_count = stats()
    expected_sum = initial_average * initial_count
    expected_count = initial_count

    values = [
        round(RNG.uniform(-97.0, 97.0), 6)
        for _ in range(rounds)
    ]
    # Always exercise the known trigger, but at an unpredictable position/value.
    trigger_position = RNG.randrange(rounds)

    for index, value in enumerate(values):
        headers = {
            random_token("X-Test-"): random_token("v"),
            random_token("X-Hidden-"): random_token("p"),
        }
        if index == trigger_position:
            headers["X-Internal-Debug"] = "admin"
        else:
            headers["X-Internal-Debug"] = random_token("role-")

        params = [
            ("value", format(value, ".6f")),
            (random_token("option"), random_token("data")),
            (random_token("mode"), str(RNG.randrange(1000000))),
        ]
        RNG.shuffle(params)
        status, _ = request("POST", "/submit?" + urllib.parse.urlencode(params), headers)
        assert status == 200, f"POST {index} failed, status: {status}"

        expected_count += 1
        expected_sum += value
        actual_average, actual_count = stats()
        assert actual_count == expected_count, (
            f"Submission {index}: expected count {expected_count}, got {actual_count}"
        )
        assert_close(actual_average, expected_sum / expected_count)


def listener_pids(port=8080):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9:
                local = fields[1]
                state = fields[3]
                if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            continue
    return pids


def stop_listener():
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.15)
    assert not listener_pids(), "Could not stop the existing listener on port 8080"


def wait_for_server(proc):
    deadline = time.time() + 6
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Daemon exited before listening (status {proc.returncode})")
        try:
            status, _ = request("GET", "/stats", timeout=0.3)
            if status == 200:
                return
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.1)
    raise AssertionError("Daemon did not listen on 127.0.0.1:8080")


def is_elf_executable(path):
    try:
        mode = path.stat().st_mode
        if not stat.S_ISREG(mode) or mode & 0o111 == 0:
            return False
        with path.open("rb") as handle:
            return handle.read(4) == b"\x7fELF"
    except OSError:
        return False


def find_compiled_artifact():
    candidates = [path for path in PROJECT.rglob("*") if is_elf_executable(path)]
    assert candidates, "No compiled ELF application was found in the project directory"
    preferred = [path for path in candidates if path.name in ("analytics-daemon", "main")]
    pool = preferred or candidates
    return max(pool, key=lambda path: path.stat().st_mtime_ns)


def exercise_binary(binary, cwd):
    stop_listener()
    proc = subprocess.Popen(
        [str(binary)], cwd=str(cwd), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        wait_for_server(proc)
        original_assertions()
        randomized_assertions()
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        stop_listener()


def main():
    assert PROJECT.is_dir(), "Vendored project directory is missing"
    assert (PROJECT / "main.go").is_file(), "main.go is missing"

    # Preserve the original requirement that the agent leave a working server running.
    deadline = time.time() + 3
    while True:
        try:
            original_assertions()
            randomized_assertions()
            break
        except (OSError, urllib.error.URLError):
            if time.time() >= deadline:
                raise AssertionError(
                    "Could not connect to the daemon at 127.0.0.1:8080. Is it running?"
                )
            time.sleep(0.1)

    # Execute the application artifact that the agent compiled.
    artifact = find_compiled_artifact()
    exercise_binary(artifact, PROJECT)

    # Independently compile and execute the submitted source so a fabricated or stale
    # binary cannot conceal unfixed vendored code.
    rebuilt = Path("/tmp/verifier-rebuilt-analytics-daemon")
    result = subprocess.run(
        ["go", "build", "-o", str(rebuilt), "."],
        cwd=str(PROJECT), capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f"Submitted Go source does not compile: {result.stderr}"
    assert is_elf_executable(rebuilt), "Rebuilt application is not an executable ELF file"
    exercise_binary(rebuilt, PROJECT)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_daemon.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
