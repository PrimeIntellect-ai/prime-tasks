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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import signal
import stat
import subprocess
import time
from pathlib import Path

import numpy as np
import pytest
import requests
from scipy.io import wavfile

URL = "http://127.0.0.1:8080/api/events"
HOME = Path("/home/user")
AUDIO = Path("/app/data/raw_audio.wav")
EVENTS = HOME / "events.json"
CPP = HOME / "detector.cpp"
PIPELINE = HOME / "pipeline.py"


def get_response(retries=10):
    response = None
    for i in range(retries):
        try:
            response = requests.get(URL, timeout=2)
            return response
        except requests.exceptions.RequestException:
            if i == retries - 1:
                pytest.fail(f"Failed to connect to the API at {URL} after {retries} attempts.")
            time.sleep(1)
    return response


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10:
                local = fields[1]
                state = fields[3]
                if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                    result.add(fields[9])
    return result


def stop_server(port=8080):
    inodes = listener_inodes(port)
    if not inodes:
        return
    targets = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) in (1, os.getpid()):
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    targets.append(int(proc.name))
                    break
        except (OSError, PermissionError):
            continue
    for pid in targets:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.1)
    for pid in targets:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def assert_payload(response, expected_events, tolerance=0.05):
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, \
        f"Expected Content-Type: application/json, got {content_type}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Failed to parse response as JSON.")

    assert "events" in data, "Response JSON is missing the 'events' key."
    events = data["events"]
    assert isinstance(events, list), "'events' should be a list."
    assert len(events) == len(expected_events), \
        f"Expected {len(expected_events)} events, got {len(events)}."

    previous_end = -1.0
    for i, expected in enumerate(expected_events):
        actual = events[i]
        assert isinstance(actual, dict), f"Event {i} should be an object."
        assert "start" in actual, f"Event {i} is missing 'start' key."
        assert "end" in actual, f"Event {i} is missing 'end' key."
        actual_start = actual["start"]
        actual_end = actual["end"]
        assert isinstance(actual_start, (int, float)) and not isinstance(actual_start, bool)
        assert isinstance(actual_end, (int, float)) and not isinstance(actual_end, bool)
        assert math.isfinite(actual_start) and math.isfinite(actual_end)
        assert actual_start < actual_end
        assert actual_start >= previous_end
        assert actual_start == round(actual_start, 2), "Start time is not rounded to two decimals."
        assert actual_end == round(actual_end, 2), "End time is not rounded to two decimals."
        previous_end = actual_end

        expected_start, expected_end = expected
        assert abs(actual_start - expected_start) <= tolerance, \
            f"Event {i} start time {actual_start} is outside tolerance of {expected_start} +/- {tolerance}"
        assert abs(actual_end - expected_end) <= tolerance, \
            f"Event {i} end time {actual_end} is outside tolerance of {expected_end} +/- {tolerance}"


def make_hidden_audio():
    sample_rate = 16000
    duration = 10.0
    seed = secrets.randbits(64)
    rng = np.random.default_rng(seed)
    signal_data = rng.normal(0, 0.035, int(sample_rate * duration))

    starts = [
        1.00 + secrets.randbelow(41) / 100.0,
        4.00 + secrets.randbelow(41) / 100.0,
        7.00 + secrets.randbelow(41) / 100.0,
    ]
    lengths = [0.30 + secrets.randbelow(21) / 100.0 for _ in starts]
    expected = []
    for start, length in zip(starts, lengths):
        start = round(start, 2)
        end = round(start + length, 2)
        begin_sample = int(round(start * sample_rate))
        end_sample = int(round(end * sample_rate))
        n = np.arange(begin_sample, end_sample)
        signal_data[begin_sample:end_sample] += 0.85 * np.sin(
            2 * np.pi * 4000 * n / sample_rate
        )
        expected.append((start, end))

    signal_data = np.clip(signal_data, -1.0, 1.0)
    wavfile.write(str(AUDIO), sample_rate, np.int16(signal_data * 32767))
    return expected


def install_compiler_probe():
    probe_dir = Path("/tmp/verifier-bin")
    probe_dir.mkdir(exist_ok=True)
    Path("/tmp/verifier-gpp.log").unlink(missing_ok=True)
    Path("/tmp/verifier-detector-ran.log").unlink(missing_ok=True)
    wrapper = probe_dir / "g++"
    wrapper.write_text(r'''#!/bin/bash
printf '%s\n' "$*" >> /tmp/verifier-gpp.log
out="a.out"
need_out=0
for arg in "$@"; do
    if [ "$need_out" = 1 ]; then out="$arg"; need_out=0; continue; fi
    case "$arg" in
        -o) need_out=1 ;;
        -o*) out="${arg#-o}" ;;
    esac
done
/usr/bin/g++ "$@"
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
case "$out" in /*) absolute="$out" ;; *) absolute="$PWD/$out" ;; esac
if [ -f "$absolute" ] && [ -x "$absolute" ]; then
    real="${absolute}.verifier-real"
    mv "$absolute" "$real"
    cat > "$absolute" <<LAUNCHER
#!/bin/bash
printf '%s\\n' "invoked" >> /tmp/verifier-detector-ran.log
exec "$real" "\$@"
LAUNCHER
    chmod +x "$absolute"
fi
''')
    wrapper.chmod(0o755)
    return probe_dir


def test_complete_pipeline_and_api():
    # Preserve the original verifier's assertions against the initially generated audio.
    initial = get_response(5)
    expected_initial = [(1.50, 2.00), (4.20, 4.60), (7.80, 8.10)]
    assert_payload(initial, expected_initial)

    assert CPP.is_file(), "/home/user/detector.cpp is missing."
    assert PIPELINE.is_file(), "/home/user/pipeline.py is missing."
    assert CPP.stat().st_size > 0, "detector.cpp is empty."
    assert PIPELINE.stat().st_size > 0, "pipeline.py is empty."

    # Independently ensure the submitted C++ source really compiles.
    compile_result = subprocess.run(
        ["/usr/bin/g++", "-std=c++17", "-O2", str(CPP), "-o", "/tmp/verifier_detector_build"],
        cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"detector.cpp did not compile:\n{compile_result.stderr}"
    built = Path("/tmp/verifier_detector_build")
    assert built.is_file() and os.access(built, os.X_OK), "Compilation did not produce an executable."

    # Replace the known fixture with unpredictable pulses, then execute the submitted workflow.
    stop_server()
    expected_hidden = make_hidden_audio()
    EVENTS.unlink(missing_ok=True)
    probe_dir = install_compiler_probe()
    env = os.environ.copy()
    env["PATH"] = str(probe_dir) + os.pathsep + env.get("PATH", "")
    proc = subprocess.Popen(
        ["python3", str(PIPELINE)], cwd=str(HOME), env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True
    )

    try:
        response = get_response(15)
        assert_payload(response, expected_hidden)

        assert Path("/tmp/verifier-gpp.log").is_file(), \
            "pipeline.py did not invoke g++ to compile the detector."
        assert Path("/tmp/verifier-detector-ran.log").is_file(), \
            "pipeline.py compiled a binary but did not execute it."
        assert EVENTS.is_file(), "/home/user/events.json was not generated."
        assert EVENTS.stat().st_size > 0, "events.json is empty."

        disk_bytes = EVENTS.read_bytes()
        assert response.content == disk_bytes, \
            "The API response is not the exact contents of events.json."
        disk_data = json.loads(disk_bytes)
        assert disk_data == response.json(), "events.json does not match the API JSON."
    finally:
        stop_server()
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
