#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import glob
import json
import os
import re
import secrets
import signal
import subprocess
import time
import urllib.request

EXPECTED_WORDS = [
    "hello", "i", "am", "calling", "because", "my", "internet", "connection",
    "is", "completely", "unresponsive", "and", "i", "demand", "an",
    "immediate", "cancellation", "of", "my", "subscription"
]
HOME = "/home/user"
TRANSCRIPT = f"{HOME}/transcript.csv"
STREAM = f"{HOME}/stream.csv"
FEED = f"{HOME}/feed.sh"
SOURCE = f"{HOME}/analyzer.cpp"
BINARY = f"{HOME}/analyzer"
TEST_BINARY = "/tmp/submitted-analyzer"


def csv_lines(words, start=0):
    return [f"{start + i},{word}" for i, word in enumerate(words)]


def read_nonempty(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def get_metrics(timeout=3):
    with urllib.request.urlopen("http://127.0.0.1:8080/metrics", timeout=timeout) as response:
        assert response.status == 200
        body = response.read().decode("utf-8")
    data = json.loads(body)
    assert "rolling_avg" in data, "JSON response missing 'rolling_avg' key."
    assert "anomalies" in data, "JSON response missing 'anomalies' key."
    return float(data["rolling_avg"]), int(data["anomalies"])


def wait_for_metrics(expected_avg, expected_anomalies, timeout=20):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = get_metrics()
            if abs(last[0] - expected_avg) < 0.005 and last[1] == expected_anomalies:
                return last
        except Exception as exc:
            last = repr(exc)
        time.sleep(0.25)
    raise AssertionError(
        f"Metrics did not become ({expected_avg}, {expected_anomalies}); last result was {last}"
    )


def derived_metrics(words):
    window = []
    anomalies = 0
    average = 0.0
    for word in words:
        window.append(len(word))
        window = window[-10:]
        average = sum(window) / len(window)
        if average > 6.0:
            anomalies += 1
    return round(average, 2), anomalies


def kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        fd_dir = procdir + "/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(fd_dir + "/" + fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    victims.add(int(procdir.rsplit("/", 1)[1]))
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    if victims:
        time.sleep(0.5)


def cron_configuration():
    chunks = []
    for user in ("user", "root"):
        result = subprocess.run(
            ["crontab", "-u", user, "-l"], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )
        if result.returncode == 0:
            chunks.append(result.stdout)
    for pattern in ("/etc/crontab", "/etc/cron.d/*", "/var/spool/cron/crontabs/*"):
        for path in glob.glob(pattern):
            try:
                with open(path, errors="replace") as f:
                    chunks.append(f.read())
            except (OSError, UnicodeError):
                pass
    return "\n".join(chunks)


def test_transcript_csv():
    assert os.path.exists(TRANSCRIPT), f"Transcript file {TRANSCRIPT} is missing."
    lines = read_nonempty(TRANSCRIPT)
    assert len(lines) == len(EXPECTED_WORDS), (
        f"Expected {len(EXPECTED_WORDS)} lines in transcript, found {len(lines)}"
    )
    for i, expected_word in enumerate(EXPECTED_WORDS):
        expected_line = f"{i},{expected_word}"
        assert lines[i] == expected_line, (
            f"Line {i} mismatch: expected '{expected_line}', got '{lines[i]}'"
        )


def test_required_artifacts_and_cron():
    assert os.path.isfile(FEED), f"Feed script {FEED} is missing."
    assert os.access(FEED, os.X_OK), f"Feed script {FEED} is not executable."
    assert os.path.isfile(SOURCE), f"C++ source {SOURCE} is missing."
    assert os.path.getsize(SOURCE) > 0, f"C++ source {SOURCE} is empty."
    assert os.path.isfile(BINARY), f"Compiled analyzer {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Compiled analyzer {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."

    subprocess.run(
        ["g++", "-std=c++17", "-O2", "-pthread", SOURCE, "-o", TEST_BINARY],
        check=True, timeout=45
    )

    cron_pids = subprocess.run(
        ["pgrep", "-x", "cron"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True
    )
    assert cron_pids.returncode == 0 and cron_pids.stdout.strip(), "The cron daemon is not running."

    config = cron_configuration()
    schedule = re.compile(
        r"(?m)^\s*\*\s+\*\s+\*\s+\*\s+\*\s+(?:\S+\s+)?[^#\n]*?/home/user/feed\.sh(?:\s|$)"
    )
    assert schedule.search(config), "No every-minute cron entry invokes /home/user/feed.sh."


def test_feed_script_and_server_metrics():
    cron_pids = [int(x) for x in subprocess.check_output(["pgrep", "-x", "cron"], text=True).split()]
    for pid in cron_pids:
        os.kill(pid, signal.SIGSTOP)

    preserved = {"transcript.csv", "feed.sh", "analyzer.cpp", "analyzer"}
    saved_files = {}
    process = None
    try:
        # Remove prior stream/state regular files so the submitted pipeline is exercised from a clean run.
        for name in os.listdir(HOME):
            path = os.path.join(HOME, name)
            if name not in preserved and (os.path.isfile(path) or os.path.islink(path)):
                if os.path.isfile(path) and not os.path.islink(path):
                    with open(path, "rb") as f:
                        saved_files[name] = (f.read(), os.stat(path).st_mode)
                os.unlink(path)

        with open(TRANSCRIPT, "w") as f:
            f.write("\n".join(csv_lines(EXPECTED_WORDS)) + "\n")
        open(STREAM, "w").close()

        kill_port_8080_listeners()
        process = subprocess.Popen(
            [TEST_BINARY], cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )

        deadline = time.time() + 10
        last_error = None
        while time.time() < deadline:
            assert process.poll() is None, "The analyzer exited before serving HTTP."
            try:
                get_metrics()
                break
            except Exception as exc:
                last_error = exc
                time.sleep(0.2)
        else:
            raise AssertionError(f"Analyzer did not start its metrics endpoint: {last_error}")

        # Preserve the original verifier's feed executions and fixed expected assertions.
        for _ in range(3):
            subprocess.run([FEED], check=True, timeout=10)
            time.sleep(0.2)

        assert read_nonempty(STREAM) == csv_lines(EXPECTED_WORDS), (
            "feed.sh did not stream the original transcript exactly once in batches."
        )
        original_avg, original_anomalies = wait_for_metrics(6.1, 7)
        assert abs(original_avg - 6.1) < 0.05, f"Expected rolling_avg ~6.1, got {original_avg}"
        assert original_anomalies == 7, f"Expected 7 anomalies, got {original_anomalies}"

        # Append unpredictable words, then verify batching, offset tracking, rolling statistics,
        # and anomaly counts using answers derived by the verifier.
        lengths = [((i * 7 + secrets.randbelow(5)) % 12) + 1 for i in range(27)]
        extra_words = [
            "".join(secrets.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(length))
            for length in lengths
        ]
        all_words = EXPECTED_WORDS + extra_words
        with open(TRANSCRIPT, "w") as f:
            f.write("\n".join(csv_lines(all_words)) + "\n")

        expected_counts = [30, 40, 47]
        for expected_count in expected_counts:
            subprocess.run([FEED], check=True, timeout=10)
            streamed = read_nonempty(STREAM)
            assert streamed == csv_lines(all_words[:expected_count]), (
                f"feed.sh did not append exactly the next batch; expected {expected_count} rows, "
                f"found {len(streamed)}"
            )

        subprocess.run([FEED], check=True, timeout=10)
        assert read_nonempty(STREAM) == csv_lines(all_words), (
            "feed.sh duplicated or altered data after the transcript was exhausted."
        )

        expected_avg, expected_anomalies = derived_metrics(all_words)
        wait_for_metrics(expected_avg, expected_anomalies)

        # Exercise repeated/concurrent requests and require stable JSON metrics.
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda _: get_metrics(5), range(12)))
        for rolling_avg, anomalies in results:
            assert abs(rolling_avg - expected_avg) < 0.005
            assert anomalies == expected_anomalies
        assert process.poll() is None, "Analyzer stopped during repeated metrics requests."
    finally:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

        with open(TRANSCRIPT, "w") as f:
            f.write("\n".join(csv_lines(EXPECTED_WORDS)) + "\n")
        for name, (content, mode) in saved_files.items():
            path = os.path.join(HOME, name)
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, mode)
        for pid in cron_pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
