#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_task.py
import csv
import math
import os
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

HOST = "127.0.0.1"
PORT = 9090
DICTATED = [20.5, 21.2, 19.8, 20.1, 99.9, 20.4, 20.6, 20.9]
PHRASE = ("twenty point five, twenty one point two, nineteen point eight, unknown, "
          "twenty point one, ninety nine point nine, twenty point four, twenty point six, "
          "error, twenty point nine")


def fail(message):
    raise AssertionError(message)


def verify_audio():
    source = Path("/app/sensor_dictation.wav")
    if not source.is_file():
        fail("/app/sensor_dictation.wav is missing")
    reference = "/tmp/reference_sensor_dictation.wav"
    subprocess.run(["espeak", "-w", reference, PHRASE], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with wave.open(str(source), "rb") as actual, wave.open(reference, "rb") as expected:
        actual_params = (actual.getnchannels(), actual.getsampwidth(), actual.getframerate(), actual.getnframes())
        expected_params = (expected.getnchannels(), expected.getsampwidth(), expected.getframerate(), expected.getnframes())
        if actual_params != expected_params or actual.readframes(actual.getnframes()) != expected.readframes(expected.getnframes()):
            fail("sensor_dictation.wav does not contain the supplied dictation")


def csv_files():
    result = []
    for root in (Path("/app"), Path("/home/user")):
        if root.exists():
            result.extend(p for p in root.rglob("*.csv") if p.is_file())
    return sorted(set(result))


def read_temperature_csv(path):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if not rows or rows[0] != ["temperature"]:
        return None
    numeric = []
    for row in rows[1:]:
        if len(row) != 1:
            return None
        text = row[0].strip()
        try:
            value = float(text)
        except ValueError:
            if text.lower() not in ("unknown", "error", ""):
                return None
            continue
        if not math.isfinite(value):
            return None
        numeric.append(value)
    return numeric


def locate_extracted_csv():
    matches = []
    for path in csv_files():
        try:
            values = read_temperature_csv(path)
        except Exception:
            continue
        if values is not None and len(values) == len(DICTATED) and all(
                abs(a - b) < 1e-9 for a, b in zip(values, DICTATED)):
            matches.append(path)
    if not matches:
        fail("No single-column temperature CSV containing the dictated readings was found")
    return matches


def calculate(values):
    mean = statistics.fmean(values)
    population_sd = math.sqrt(sum((x - mean) ** 2 for x in values) / len(values))
    cleaned = [x for x in values if abs(x - mean) <= 3.0 * population_sd]
    removed = len(values) - len(cleaned)
    cleaned_mean = statistics.fmean(cleaned)
    sample_sd = statistics.stdev(cleaned) if len(cleaned) > 1 else 0.0
    margin = 1.96 * sample_sd / math.sqrt(len(cleaned))
    return cleaned_mean, cleaned_mean - margin, cleaned_mean + margin, removed


def send(command, expect_response=True):
    with socket.create_connection((HOST, PORT), timeout=2.0) as sock:
        sock.settimeout(1.0)
        sock.sendall(command.encode("utf-8"))
        try:
            data = sock.recv(4096)
        except (socket.timeout, ConnectionResetError):
            data = b""
    text = data.decode("utf-8", errors="strict")
    if expect_response and not text:
        fail("Server returned no response for " + command.strip())
    return text


def exercise(values):
    mean, low, high, outliers = calculate(values)
    expected_mean = f"Mean: {mean:.2f}"
    expected_ci = f"CI: [{low:.2f}, {high:.2f}]"
    expected_outliers = f"Outliers: {outliers}"
    actual = send("GET_MEAN\n").strip()
    if actual != expected_mean:
        fail(f"Expected {expected_mean!r}, got {actual!r}")
    actual = send("GET_CI\n").strip()
    if actual != expected_ci:
        fail(f"Expected {expected_ci!r}, got {actual!r}")
    actual = send("AUTH mysecrettoken GET_OUTLIER_COUNT\n").strip()
    if actual != expected_outliers:
        fail(f"Expected {expected_outliers!r}, got {actual!r}")
    actual = send("GET_OUTLIER_COUNT\n", expect_response=False).strip()
    if actual:
        fail(f"Unauthenticated outlier command returned {actual!r}")


def listener_pid():
    inode = None
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if int(local.rsplit(":", 1)[1], 16) == PORT and state == "0A":
                inode = fields[9]
                break
        if inode:
            break
    if not inode:
        return None
    needle = "socket:[%s]" % inode
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    if os.readlink(fd) == needle:
                        return int(proc.name)
                except OSError:
                    pass
        except OSError:
            pass
    return None


def wait_for_server(timeout=4.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = listener_pid()
        if pid is not None:
            return pid
        time.sleep(0.05)
    return None


def stop_pid(pid):
    if not pid:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(20):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.15)


def start_program(executable, args, cwd):
    proc = subprocess.Popen([executable] + args, cwd=cwd, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True)
    pid = wait_for_server()
    if pid is None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        return None, proc
    return pid, proc


def c_sources():
    candidates = []
    for root in (Path("/app"), Path("/home/user")):
        if not root.exists():
            continue
        for path in root.rglob("*.c"):
            try:
                data = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            if all(token in data for token in ("GET_MEAN", "GET_CI", "GET_OUTLIER_COUNT")) and \
                    ("socket(" in data or "socket (" in data) and ("bind(" in data or "bind (" in data):
                candidates.append(path)
    if not candidates:
        fail("No C server source implementing the required protocol was found")
    return candidates


def compile_candidates(sources):
    outputs = []
    for index, source in enumerate(sources):
        output = f"/tmp/submitted_server_{index}"
        command = ["gcc", "-O2", "-std=c11", str(source), "-o", output, "-lm", "-pthread"]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        if result.returncode == 0:
            outputs.append(output)
    if not outputs:
        fail("The submitted C server source does not compile")
    return outputs


def main():
    verify_audio()
    extracted = locate_extracted_csv()
    exercise(DICTATED)

    pid = listener_pid()
    if pid is None:
        fail("No server is listening on 127.0.0.1:9090")
    exe = os.readlink(f"/proc/{pid}/exe")
    if exe.endswith(" (deleted)"):
        fail("The running server executable was deleted")
    with open(exe, "rb") as handle:
        if handle.read(4) != b"\x7fELF":
            fail("The listening server is not a compiled executable")
    cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    args = [x.decode(errors="surrogateescape") for x in cmdline[1:] if x]
    cwd = os.readlink(f"/proc/{pid}/cwd")

    sources = c_sources()
    compiled = compile_candidates(sources)
    all_csv = csv_files()
    backups = {path: path.read_bytes() for path in all_csv}
    random_values = [float(x) for x in range(10, 30)] + [1000.0]
    random_csv = "temperature\nunknown\n" + "\n".join(str(x) for x in random_values) + "\nerror\n"

    stop_pid(pid)
    active_pid = None
    try:
        for path in all_csv:
            path.write_text(random_csv, encoding="utf-8")

        active_pid, proc = start_program(exe, args, cwd)
        if active_pid is None:
            fail("The submitted server executable could not be restarted")
        exercise(random_values)
        stop_pid(active_pid)
        active_pid = None

        compiled_ok = False
        for binary in compiled:
            candidate_pid, proc = start_program(binary, args, cwd)
            if candidate_pid is None:
                continue
            try:
                exercise(random_values)
                compiled_ok = True
            except Exception:
                pass
            finally:
                stop_pid(candidate_pid)
            if compiled_ok:
                break
        if not compiled_ok:
            fail("Compiled submitted C source did not calculate statistics from changed CSV input")
    finally:
        if active_pid:
            stop_pid(active_pid)
        for path, content in backups.items():
            try:
                path.write_bytes(content)
            except OSError:
                pass
        # Restore the required continuously running service with the original data.
        if listener_pid() is None:
            start_program(exe, args, cwd)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"VERIFICATION FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
PY

if python3 /tmp/verify_task.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
