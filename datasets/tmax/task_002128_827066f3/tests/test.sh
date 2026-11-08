#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import stat
import subprocess
import time

import pytest
import requests

SCRIPT = "/home/user/pipeline.sh"
CSV_PATH = "/home/user/clean_telemetry.csv"
VIDEO_PATH = "/app/telemetry.mp4"


def stop_old_pipeline_and_listener():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read()
            args = [x.decode(errors="ignore") for x in raw.split(b"\0") if x]
            if SCRIPT in args:
                os.kill(int(entry), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if int(fields[1].split(":")[-1], 16) == 8080 and fields[3] == "0A":
                        listener_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    if listener_inodes:
        for entry in os.listdir("/proc"):
            if not entry.isdigit() or int(entry) == me:
                continue
            fd_dir = f"/proc/{entry}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f"{fd_dir}/{fd}")
                    except (FileNotFoundError, PermissionError):
                        continue
                    if any(target == f"socket:[{inode}]" for inode in listener_inodes):
                        try:
                            os.kill(int(entry), signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                        break
            except (FileNotFoundError, PermissionError):
                pass
    time.sleep(0.2)


def make_dynamic_video():
    base = 1750000000 + secrets.randbelow(100000000)
    temperatures = [
        (secrets.randbelow(500) - 150) / 10.0,
        (secrets.randbelow(400) - 100) / 10.0,
        (secrets.randbelow(600) - 250) / 10.0,
        (secrets.randbelow(450) - 120) / 10.0,
    ]
    humidities = [
        (secrets.randbelow(700) + 100) / 10.0,
        None,
        (secrets.randbelow(500) + 300) / 10.0,
        None,
    ]
    statuses = ["alpha\\u002Xmode", "beta\\u002Xstate", "normal", "gamma\\u002Xmode"]

    srt_path = f"/tmp/telemetry-{secrets.token_hex(8)}.srt"
    with open(srt_path, "w") as f:
        for i, (temp, humidity, status) in enumerate(zip(temperatures, humidities, statuses), 1):
            h_text = "null" if humidity is None else json.dumps(humidity)
            payload = (
                f'{{"ts": {base + i - 1}, "t": {json.dumps(temp)}, '
                f'"h": {h_text}, "status": "{status}"}}'
            )
            f.write(f"{i}\n00:00:0{i},000 --> 00:00:0{i + 1},000\n{payload}\n\n")

    try:
        subprocess.run(
            [
                "ffmpeg", "-loglevel", "error", "-y",
                "-f", "lavfi", "-i", "color=c=black:s=320x240:d=6",
                "-i", srt_path,
                "-c:v", "libx264", "-c:s", "mov_text",
                "-map", "0:v", "-map", "1:s", VIDEO_PATH,
            ],
            check=True,
        )
    finally:
        os.unlink(srt_path)


def derive_expected_from_video():
    extracted = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", VIDEO_PATH, "-map", "0:s:0", "-f", "srt", "-"],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout

    expected = []
    payload_count = 0
    for line in extracted.splitlines():
        if not line.startswith("{"):
            continue
        payload_count += 1
        corrected = line.replace("\\u002X", "\\u0020")
        record = json.loads(corrected)
        expected.append((str(record["ts"]), "t", float(record["t"]) * 1.8 + 32.0))
        humidity = 50.0 if record.get("h") is None else float(record["h"])
        expected.append((str(record["ts"]), "h", humidity))

    assert payload_count >= 4, "Verifier failed to create/extract its dynamic telemetry records"
    return expected


def parse_csv(text):
    parsed = []
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.strip().split(",")
        assert len(parts) == 3, f"Malformed CSV line: {line!r}"
        assert parts[1] in ("t", "h"), f"Unexpected metric in line: {line!r}"
        try:
            value = float(parts[2])
        except ValueError:
            pytest.fail(f"Non-numeric CSV value in line: {line!r}")
        parsed.append((parts[0], parts[1], value))
    return parsed


def assert_records(actual, expected):
    assert len(actual) == len(expected), f"Expected exactly {len(expected)} records, found {len(actual)}: {actual}"
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert got[0] == wanted[0], f"Wrong timestamp at record {index}: {got} != {wanted}"
        assert got[1] == wanted[1], f"Wrong metric at record {index}: {got} != {wanted}"
        assert abs(got[2] - wanted[2]) < 0.01, f"Wrong value at record {index}: {got} != {wanted}"


@pytest.fixture(scope="session")
def dynamic_run():
    stop_old_pipeline_and_listener()
    make_dynamic_video()
    expected = derive_expected_from_video()

    try:
        os.unlink(CSV_PATH)
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(
        [SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 12
    while time.time() < deadline:
        if os.path.exists(CSV_PATH) and os.path.getsize(CSV_PATH) > 0:
            break
        if proc.poll() is not None:
            pytest.fail(f"Pipeline exited with status {proc.returncode} before producing output")
        time.sleep(0.1)
    else:
        pytest.fail(f"Output file {CSV_PATH} was not produced in time")

    # The CSV is written immediately before the listener is normally started.
    # Wait briefly rather than probing the one-shot server and consuming it.
    time.sleep(0.5)
    yield expected, proc

    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


def test_pipeline_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SCRIPT} is not executable."


def test_csv_output(dynamic_run):
    expected, _ = dynamic_run
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    with open(CSV_PATH) as f:
        actual = parse_csv(f.read())
    assert_records(actual, expected)


def test_http_server(dynamic_run):
    expected, _ = dynamic_run
    # Make exactly one request so a compliant one-shot server is not consumed by a probe.
    try:
        response = requests.get("http://127.0.0.1:8080", timeout=4)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to HTTP server on port 8080: {exc}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    actual = parse_csv(response.text)
    assert_records(actual, expected)

    with open(CSV_PATH) as f:
        persisted = parse_csv(f.read())
    assert_records(actual, persisted)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
