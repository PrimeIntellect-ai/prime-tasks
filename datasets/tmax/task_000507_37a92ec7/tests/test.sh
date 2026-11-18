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

cat << 'PY_EOF' > /tmp/verify_task.py
import csv
import glob
import os
import secrets
import shutil
import signal
import subprocess
import time

import requests

BASE = "http://127.0.0.1:8080"
HEADER = "timestamp,value,rolling_avg"

ORIGINAL = {
    "zone_alpha": (
        "timestamp,value,rolling_avg\n"
        "100,10.00,10.00\n"
        "101,15.00,12.50\n"
        "102,14.00,13.00\n"
        "103,20.00,16.33\n"
        "104,22.00,18.67"
    ),
    "zone_beta": (
        "timestamp,value,rolling_avg\n"
        "100,5.00,5.00\n"
        "101,6.00,5.50\n"
        "102,8.00,6.33\n"
        "103,7.00,7.00\n"
        "104,10.00,8.33"
    ),
    "zone_gamma": (
        "timestamp,value,rolling_avg\n"
        "100,100.00,100.00\n"
        "101,90.00,95.00\n"
        "102,80.00,90.00\n"
        "103,85.00,85.00\n"
        "104,88.00,84.33"
    ),
}


def get(zone, timeout=5):
    return requests.get(BASE + "/rolling", params={"zone": zone}, timeout=timeout)


# Preserve all assertions made by the original verifier.
for zone, expected in ORIGINAL.items():
    response = get(zone)
    assert response.status_code == 200, (
        f"Expected status code 200 for {zone}, got {response.status_code}"
    )
    if zone == "zone_alpha":
        assert "text/csv" in response.headers.get("Content-Type", ""), (
            "Expected Content-Type to include text/csv"
        )
    actual = response.text.strip().replace("\r\n", "\n")
    assert actual == expected, (
        f"Response for {zone} did not match expected CSV.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


# A C++ source artifact must remain in the submitted workspace.
sources = []
for root in ("/app", "/home/user"):
    for ext in ("*.cpp", "*.cc", "*.cxx", "*.c++"):
        sources.extend(glob.glob(os.path.join(root, "**", ext), recursive=True))
assert any(os.path.isfile(p) and os.path.getsize(p) > 0 for p in sources), (
    "No non-empty C++ source artifact was found"
)


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if fields[1].rsplit(":", 1)[-1].upper() == wanted:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    found = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[-1])
        for fd in glob.glob(procdir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                found.add(pid)
                break
    return sorted(found)


pids = listener_pids(8080)
assert pids, "No process is listening on the required port 8080"
pid = pids[0]
proc_exe = f"/proc/{pid}/exe"
exe_link = os.readlink(proc_exe)
exe_name = os.path.basename(exe_link.replace(" (deleted)", "")).lower()
assert exe_name not in {
    "python", "python3", "python3.11", "bash", "sh", "dash", "node",
    "nodejs", "ruby", "perl", "php"
}, f"The listening process is an interpreter ({exe_name}), not the C++ server artifact"
with open(proc_exe, "rb") as f:
    assert f.read(4) == b"\x7fELF", "The listening server is not a native executable"
with open(f"/proc/{pid}/maps", errors="replace") as f:
    maps = f.read()
assert "libstdc++" in maps, "The listening native server is not linked to the C++ runtime"

with open(f"/proc/{pid}/cmdline", "rb") as f:
    argv = [x.decode(errors="surrogateescape") for x in f.read().split(b"\0") if x]
assert argv, "Could not determine the server command line"
try:
    cwd = os.readlink(f"/proc/{pid}/cwd")
except OSError:
    cwd = "/app"
try:
    with open(f"/proc/{pid}/environ", "rb") as f:
        env_items = [x for x in f.read().split(b"\0") if b"=" in x]
    env = {
        k.decode(errors="surrogateescape"): v.decode(errors="surrogateescape")
        for k, v in (item.split(b"=", 1) for item in env_items)
    }
except OSError:
    env = os.environ.copy()

# Preserve a runnable copy if the executable was unlinked after startup.
clean_exe = exe_link.replace(" (deleted)", "")
if os.path.isfile(clean_exe) and os.access(clean_exe, os.X_OK):
    launch_exe = clean_exe
else:
    launch_exe = "/tmp/submitted_cpp_server"
    shutil.copy2(proc_exe, launch_exe)
    os.chmod(launch_exe, 0o755)
launch_argv = [launch_exe] + argv[1:]

# Replace the input with unpredictable, shuffled wide-format data. Expected
# answers are independently derived here, so fixed responses cannot pass.
nonce = secrets.randbelow(50000) + 20000
timestamps = [nonce + i * 7 for i in range(7)]
values = {
    "zone_alpha": [secrets.randbelow(80) + 10 for _ in timestamps],
    "zone_beta": [secrets.randbelow(120) + 30 for _ in timestamps],
    "zone_gamma": [secrets.randbelow(200) + 100 for _ in timestamps],
}
order = [4, 0, 6, 2, 5, 1, 3]
with open("/app/system_metrics.bin", "w", encoding="iso-8859-1", newline="") as f:
    writer = csv.writer(f, lineterminator="\n")
    writer.writerow(["timestamp", "zone_alpha", "zone_beta", "zone_gamma"])
    for i in order:
        writer.writerow([
            timestamps[i], values["zone_alpha"][i],
            values["zone_beta"][i], values["zone_gamma"][i]
        ])

# Stop the submitted instance and explicitly execute the discovered C++ artifact
# again so it must process the replacement file.
for old_pid in pids:
    try:
        os.kill(old_pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
for _ in range(30):
    if not listener_pids(8080):
        break
    time.sleep(0.1)
for old_pid in listener_pids(8080):
    try:
        os.kill(old_pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
time.sleep(0.2)

proc = subprocess.Popen(
    launch_argv,
    cwd=cwd if os.path.isdir(cwd) else "/app",
    env=env,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
)

last_error = None
for _ in range(60):
    try:
        response = get("zone_alpha", timeout=0.5)
        if response.status_code == 200:
            break
    except requests.RequestException as exc:
        last_error = exc
    time.sleep(0.1)
else:
    raise AssertionError(f"Re-executed C++ server did not become ready: {last_error}")


def expected_csv(zone):
    lines = [HEADER]
    series = values[zone]
    for i, (ts, value) in enumerate(zip(timestamps, series)):
        window = series[max(0, i - 2):i + 1]
        average = sum(window) / len(window)
        lines.append(f"{ts},{value:.2f},{average:.2f}")
    return "\n".join(lines)


for zone in ("zone_alpha", "zone_beta", "zone_gamma"):
    response = get(zone)
    assert response.status_code == 200, (
        f"Expected status code 200 for dynamic {zone}, got {response.status_code}"
    )
    assert "text/csv" in response.headers.get("Content-Type", ""), (
        f"Expected text/csv Content-Type for dynamic {zone}"
    )
    expected = expected_csv(zone)
    actual = response.text.strip().replace("\r\n", "\n")
    assert actual == expected, (
        f"Dynamic response for {zone} was incorrect.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
