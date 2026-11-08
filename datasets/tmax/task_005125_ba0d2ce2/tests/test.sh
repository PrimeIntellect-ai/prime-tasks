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
import os
import re
import stat
import time
import shutil
import subprocess
import base64
import requests
import pytest

CLEANED_PATH = '/home/user/cleaned_data.csv'
REPORT_PATH = '/home/user/report.html'
SERVER_PATH = '/home/user/server.sh'


def get_expected_data():
    raw_file = '/home/user/raw_sensor_logs.txt'
    if not os.path.exists(raw_file):
        return [], 0

    with open(raw_file, 'r') as f:
        lines = f.read().splitlines()

    valid_rows = []
    for line in lines:
        if not line.strip():
            continue
        try:
            b = base64.b64decode(line)
            dec = bytes([x ^ 0x42 for x in b]).decode('utf-8')
        except Exception:
            continue

        parts = dec.strip().split(',')
        if len(parts) != 3:
            continue

        ts, sid, val = parts

        if val == "ERROR":
            continue
        try:
            if float(val) < 0:
                continue
        except ValueError:
            pass

        sid = sid.upper()
        valid_rows.append(f"{ts},{sid},{val}")

    unique_rows = list(set(valid_rows))
    # Standard linux sort behavior (lexicographical)
    unique_rows.sort()

    sensors = set(row.split(',')[1] for row in unique_rows)
    return unique_rows, len(sensors)


def expected_outputs():
    rows, sensor_count = get_expected_data()
    csv_text = "\n".join(rows)
    if csv_text:
        csv_text += "\n"
    html_text = f"""<html>
<body>
<h1>Sensor Data Report</h1>
<p>Total Cleaned Records: {len(rows)}</p>
<p>Unique Sensors: {sensor_count}</p>
</body>
</html>"""
    return csv_text, html_text


def assert_regular_file(path):
    assert os.path.exists(path), f"Required artifact does not exist: {path}"
    mode = os.stat(path, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"Required artifact is not a regular file: {path}"


def read_cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
    except OSError:
        return []


def read_ppid(pid):
    try:
        with open(f'/proc/{pid}/status', 'r') as f:
            for line in f:
                if line.startswith('PPid:'):
                    return int(line.split()[1])
    except (OSError, ValueError):
        pass
    return 0


def read_exe(pid):
    try:
        return os.path.realpath(os.readlink(f'/proc/{pid}/exe'))
    except OSError:
        return ''


def listener_inodes():
    found = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table, 'r') as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    address, port_hex = local.rsplit(':', 1)
                    if int(port_hex, 16) != 9090 or state != '0A':
                        continue
                    # Require the listener to be bound specifically to 127.0.0.1.
                    if table.endswith('tcp') and address != '0100007F':
                        continue
                    if table.endswith('tcp6') and address not in {
                        '0000000000000000FFFF00000100007F',
                        '00000000000000000000000001000000'
                    }:
                        continue
                    found.add(inode)
        except OSError:
            pass
    return found


def pids_owning_inodes(inodes):
    owners = set()
    if not inodes:
        return owners
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    owners.add(int(name))
                    break
        except OSError:
            continue
    return owners


def assert_bash_nc_listener():
    allowed = set()
    for command in ('nc', 'netcat', 'socat'):
        path = shutil.which(command)
        if path:
            allowed.add(os.path.realpath(path))

    deadline = time.time() + 3
    while time.time() < deadline:
        owners = pids_owning_inodes(listener_inodes())
        for pid in owners:
            if read_exe(pid) not in allowed:
                continue

            ancestor = read_ppid(pid)
            while ancestor > 1:
                exe = read_exe(ancestor)
                cmdline = read_cmdline(ancestor)
                if os.path.basename(exe) == 'bash' and SERVER_PATH in cmdline:
                    return
                ancestor = read_ppid(ancestor)
        time.sleep(0.1)

    pytest.fail('Port 9090 is not owned by nc/socat launched from the required Bash server.sh')


def test_required_artifacts_and_implementation():
    for path in (CLEANED_PATH, REPORT_PATH, SERVER_PATH):
        assert_regular_file(path)

    expected_csv, expected_html = expected_outputs()
    with open(CLEANED_PATH, 'r') as f:
        actual_csv = f.read()
    assert actual_csv.strip() == expected_csv.strip(), \
        'cleaned_data.csv does not match the expected filtered, normalized, deduplicated, and sorted data.'

    with open(REPORT_PATH, 'r') as f:
        actual_html = f.read()
    assert actual_html.strip().replace('\r\n', '\n') == expected_html.strip().replace('\r\n', '\n'), \
        'report.html does not match the required HTML template and counts.'

    with open(SERVER_PATH, 'r') as f:
        script = f.read()

    first_line = script.splitlines()[0] if script.splitlines() else ''
    assert re.match(r'^#!.*\bbash\b', first_line), 'server.sh must be a Bash script.'

    syntax = subprocess.run(['bash', '-n', SERVER_PATH], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    assert syntax.returncode == 0, f'server.sh has invalid Bash syntax: {syntax.stderr}'

    executable_text = '\n'.join(
        line for line in script.splitlines() if not line.lstrip().startswith('#')
    )
    assert not re.search(r'(^|[;&|()\s])(python(?:[0-9.]*)?|node(?:js)?|perl|ruby|php)(?=$|[;&|()\s])',
                         executable_text, re.IGNORECASE), \
        'server.sh must not invoke a high-level language runtime.'
    assert re.search(
        r'\b(?:while|until|for)\b[\s\S]*?\bdo\b[\s\S]*?\b(?:nc|netcat|socat)\b[\s\S]*?\bdone\b',
        executable_text
    ), 'server.sh must invoke nc or socat within a loop.'

    assert_bash_nc_listener()


def test_server_cleaned_data():
    expected_rows, _ = get_expected_data()
    expected_csv = "\n".join(expected_rows)
    if expected_csv:
        expected_csv += "\n"

    try:
        response = requests.get("http://127.0.0.1:9090/cleaned_data.csv", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or fetch /cleaned_data.csv: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    actual_text = response.text.strip()
    expected_text = expected_csv.strip()

    assert actual_text == expected_text, "The served cleaned_data.csv content does not match the expected filtered, normalized, and sorted data."


def test_server_report_html():
    expected_rows, sensor_count = get_expected_data()
    count = len(expected_rows)

    expected_html = f"""<html>
<body>
<h1>Sensor Data Report</h1>
<p>Total Cleaned Records: {count}</p>
<p>Unique Sensors: {sensor_count}</p>
</body>
</html>"""

    try:
        response = requests.get("http://127.0.0.1:9090/report.html", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or fetch /report.html: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    actual_html = response.text.strip().replace('\r\n', '\n')
    expected_html_clean = expected_html.strip().replace('\r\n', '\n')

    assert actual_html == expected_html_clean, "The served report.html content does not match the expected HTML template and counts."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
