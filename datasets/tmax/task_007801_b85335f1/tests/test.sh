#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import stat
import subprocess
import time
import uuid


def read_alert(path):
    assert os.path.isfile(path), f"Log file {path} was not created."
    with open(path, "r") as f:
        return f.read().strip()


def directory_size(path):
    result = subprocess.run(
        ["du", "-sb", path], capture_output=True, text=True, check=True
    )
    return int(result.stdout.split()[0])


def clear_directory(path):
    for name in os.listdir(path):
        item = os.path.join(path, name)
        if os.path.isdir(item) and not os.path.islink(item):
            shutil.rmtree(item)
        else:
            os.unlink(item)


def test_disk_monitor_script():
    script_path = "/home/user/disk_monitor.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    log_path = "/home/user/monitor_alert.log"
    data_dir = "/home/user/migration_data"
    backup_dir = f"/tmp/migration_data_backup_{uuid.uuid4().hex}"

    # Preserve the original assertion against the setup's approximately 2 MB tree.
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {script_path} failed with error:\n{result.stderr}"
    content = read_alert(log_path)
    assert content == "QUOTA_EXCEEDED", f"Expected 'QUOTA_EXCEEDED', got '{content}'"

    shutil.move(data_dir, backup_dir)
    os.makedirs(data_dir)

    try:
        # Preserve the original empty-directory assertion.
        result = subprocess.run(["bash", script_path], capture_output=True, text=True)
        assert result.returncode == 0, f"Running {script_path} failed on empty dir."
        content = read_alert(log_path)
        assert content == "OK", f"Expected 'OK' for small directory, got '{content}'"

        def run_generated_case(payload_size):
            clear_directory(data_dir)
            filename = os.path.join(data_dir, f"case_{uuid.uuid4().hex}.bin")
            with open(filename, "wb") as f:
                f.truncate(payload_size)
            measured = directory_size(data_dir)
            expected = "QUOTA_EXCEEDED" if measured > 1000000 else "OK"
            result = subprocess.run(["bash", script_path], capture_output=True, text=True)
            assert result.returncode == 0, (
                f"Running {script_path} failed for a generated {measured}-byte directory: "
                f"{result.stderr}"
            )
            actual = read_alert(log_path)
            assert actual == expected, (
                f"For a directory measured at {measured} bytes, expected {expected}, got {actual}"
            )
            return filename, measured

        # Random nonempty cases on both sides prevent an empty/nonempty shortcut.
        run_generated_case(random.SystemRandom().randint(100000, 850000))
        run_generated_case(random.SystemRandom().randint(1100000, 1500000))

        # Exercise the strict threshold at exactly 1,000,000 bytes and one byte over.
        clear_directory(data_dir)
        filename = os.path.join(data_dir, f"boundary_{uuid.uuid4().hex}.bin")
        with open(filename, "wb"):
            pass
        size = 0
        for _ in range(4):
            measured = directory_size(data_dir)
            size += 1000000 - measured
            assert size >= 0
            with open(filename, "r+b") as f:
                f.truncate(size)
            if directory_size(data_dir) == 1000000:
                break
        assert directory_size(data_dir) == 1000000, "Could not construct threshold test directory."

        result = subprocess.run(["bash", script_path], capture_output=True, text=True)
        assert result.returncode == 0
        assert read_alert(log_path) == "OK", "Exactly 1000000 bytes must be reported as OK."

        with open(filename, "r+b") as f:
            f.truncate(size + 1)
        assert directory_size(data_dir) == 1000001
        result = subprocess.run(["bash", script_path], capture_output=True, text=True)
        assert result.returncode == 0
        assert read_alert(log_path) == "QUOTA_EXCEEDED", (
            "A directory strictly greater than 1000000 bytes must exceed the quota."
        )
    finally:
        if os.path.exists(data_dir):
            shutil.rmtree(data_dir)
        shutil.move(backup_dir, data_dir)


def test_crontab_scheduled():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."

    crontab_lines = result.stdout.strip().split('\n')
    found = False
    for line in crontab_lines:
        if line.startswith('#'):
            continue
        normalized = re.sub(r'\s+', ' ', line.strip())
        if normalized == "* * * * * /home/user/disk_monitor.sh":
            found = True
            break

    assert found, "Could not find '* * * * * /home/user/disk_monitor.sh' in crontab."


def process_is_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def test_start_pipeline_script():
    script_path = "/home/user/start_pipeline.sh"
    fetcher_path = "/home/user/fetcher.sh"
    processor_path = "/home/user/processor.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    fetcher_original = open(fetcher_path, "rb").read()
    processor_original = open(processor_path, "rb").read()
    fetcher_mode = stat.S_IMODE(os.stat(fetcher_path).st_mode)
    processor_mode = stat.S_IMODE(os.stat(processor_path).st_mode)

    server_program = "/tmp/verifier_pipeline_server.py"
    ready_file = "/tmp/verifier_fetcher_ready"
    fetcher_marker = "/tmp/verifier_fetcher_invoked"
    processor_marker = "/tmp/verifier_processor_invoked"
    status_log = "/home/user/pipeline_status.log"
    pids_file = "/home/user/pipeline.pids"
    active_pids = set()

    with open(server_program, "w") as f:
        f.write('''import socket, time\ns = socket.socket()\ns.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\ns.bind(("127.0.0.1", 8888))\nwith open("/tmp/verifier_fetcher_ready", "w") as out:\n    out.write(str(time.time_ns()))\ns.listen(16)\nwhile True:\n    conn, _ = s.accept()\n    conn.close()\n''')

    processor_fixture = '''#!/bin/bash
echo "$$ $(date +%s%N)" > /tmp/verifier_processor_invoked
if ! nc -z 127.0.0.1 8888; then
    echo "FAILED: Port not open" > /home/user/pipeline_status.log
    exit 1
fi
echo "SUCCESS: Processor connected" > /home/user/pipeline_status.log
exec sleep 60
'''

    def stop_active():
        for pid in list(active_pids):
            subprocess.run(["kill", str(pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        active_pids.clear()
        time.sleep(0.15)

    def run_scenario(delay, timeout=15):
        stop_active()
        subprocess.run(
            ["pkill", "-f", "python3 -m http.server 8888"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for path in [ready_file, fetcher_marker, processor_marker, status_log, pids_file]:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        fetcher_fixture = f'''#!/bin/bash
echo "$$" > {fetcher_marker}
sleep {delay:.6f}
exec python3 {server_program}
'''
        with open(fetcher_path, "w") as f:
            f.write(fetcher_fixture)
        os.chmod(fetcher_path, 0o755)
        with open(processor_path, "w") as f:
            f.write(processor_fixture)
        os.chmod(processor_path, 0o755)

        started = time.monotonic()
        try:
            result = subprocess.run(
                ["bash", script_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=timeout,
            )
            assert result.returncode == 0, f"{script_path} failed to execute."
        except subprocess.TimeoutExpired:
            assert False, f"{script_path} timed out. It should run processes in the background and exit."
        elapsed = time.monotonic() - started

        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and not os.path.exists(processor_marker):
            time.sleep(0.05)

        assert os.path.isfile(pids_file), f"{pids_file} was not created."
        with open(pids_file, "r") as f:
            lines = f.read().strip().split('\n')
        assert len(lines) == 2, f"Expected exactly 2 lines in {pids_file}, found {len(lines)}."
        assert lines[0].isdigit(), f"First line of {pids_file} is not a valid PID: {lines[0]}"
        assert lines[1].isdigit(), f"Second line of {pids_file} is not a valid PID: {lines[1]}"

        fetch_pid, processor_pid = map(int, lines)
        active_pids.update([fetch_pid, processor_pid])
        assert os.path.isfile(fetcher_marker), "The required fetcher script was not launched."
        assert os.path.isfile(processor_marker), "The required processor script was not launched."

        recorded_fetch_pid = int(open(fetcher_marker).read().strip())
        processor_parts = open(processor_marker).read().strip().split()
        assert len(processor_parts) == 2
        recorded_processor_pid = int(processor_parts[0])
        processor_started_ns = int(processor_parts[1])
        assert fetch_pid == recorded_fetch_pid, "The first PID is not the launched fetcher's PID."
        assert processor_pid == recorded_processor_pid, "The second PID is not the launched processor's PID."
        assert process_is_alive(fetch_pid), "The recorded fetcher PID is not running."
        assert process_is_alive(processor_pid), "The recorded processor PID is not running."

        assert os.path.isfile(ready_file), "The fetcher never opened port 8888."
        ready_ns = int(open(ready_file).read().strip())
        assert processor_started_ns >= ready_ns, "The processor was started before port 8888 became ready."

        assert os.path.isfile(status_log), (
            f"{status_log} was not created. The processor might not have run or failed."
        )
        with open(status_log, "r") as f:
            status = f.read().strip()
        assert "SUCCESS" in status, (
            f"Expected 'SUCCESS' in {status_log}, got: '{status}'. Port 8888 was likely not ready when processor started."
        )
        return elapsed

    try:
        # A fast and a delayed service require readiness-based polling rather than a fixed sleep.
        fast_elapsed = run_scenario(random.SystemRandom().uniform(0.3, 0.7))
        assert fast_elapsed < 5.5, "Startup did not react to the service becoming ready promptly."
        run_scenario(random.SystemRandom().uniform(6.0, 7.0))
    finally:
        stop_active()
        subprocess.run(
            ["pkill", "-f", server_program],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        with open(fetcher_path, "wb") as f:
            f.write(fetcher_original)
        os.chmod(fetcher_path, fetcher_mode)
        with open(processor_path, "wb") as f:
            f.write(processor_original)
        os.chmod(processor_path, processor_mode)
        try:
            os.remove(server_program)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
