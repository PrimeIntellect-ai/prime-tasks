#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_restore.py
import glob
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import uuid

HOME = "/home/user"
SCRIPT = f"{HOME}/run_restore.py"
FSTAB = f"{HOME}/user_backup.fstab"
MOCK = f"{HOME}/mock_container.py"
LOG = f"{HOME}/restore_process.log"


def clean_outputs():
    shutil.rmtree(f"{HOME}/restore", ignore_errors=True)
    for path in glob.glob(LOG + "*"):
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
        elif os.path.isdir(path):
            shutil.rmtree(path)


def run_submission(env=None, timeout=8):
    started = time.monotonic()
    proc = subprocess.Popen(
        [sys.executable, SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError("run_restore.py did not finish in time")
    elapsed = time.monotonic() - started
    assert proc.returncode == 0, f"run_restore.py failed: {stderr or stdout}"
    return elapsed


def assert_original_final_state():
    expected_symlinks = {
        "/home/user/restore/app1/config.json": "/home/user/backup_data/app1/config.json",
        "/home/user/restore/app1/data.db": "/home/user/backup_data/app1/data.db",
        "/home/user/restore/app2/cache.bin": "/home/user/backup_data/app2/cache.bin"
    }

    for link_path, target_path in expected_symlinks.items():
        assert os.path.exists(link_path), f"Expected symlink {link_path} does not exist"
        assert os.path.islink(link_path), f"Path {link_path} is not a symlink"
        assert os.readlink(link_path) == target_path, f"Symlink {link_path} points to {os.readlink(link_path)}, expected {target_path}"

    missing_dest = "/home/user/restore/missing"
    assert not os.path.exists(missing_dest), f"Directory {missing_dest} should not have been created"

    log_files = [LOG, LOG + ".1", LOG + ".2"]
    for log_file in log_files:
        assert os.path.exists(log_file), f"Log file {log_file} does not exist"
        assert os.path.isfile(log_file), f"Path {log_file} is not a file"

    size_1 = os.path.getsize(LOG + ".1")
    size_2 = os.path.getsize(LOG + ".2")
    assert 500 < size_1 < 2000, f"Rotated log 1 size {size_1} is not close to 1024 bytes"
    assert 500 < size_2 < 2000, f"Rotated log 2 size {size_2} is not close to 1024 bytes"
    assert not os.path.exists(LOG + ".3"), "Found restore_process.log.3, but backupCount should be 2"

    content = ""
    for log_file in log_files:
        if os.path.exists(log_file):
            with open(log_file, "r", encoding="utf-8") as f:
                content += f.read()
    assert "Log line" in content, "Mock container output not found in log files"


def main():
    assert os.path.isfile(SCRIPT), "Missing /home/user/run_restore.py"
    with open(FSTAB, "rb") as f:
        original_fstab = f.read()
    with open(MOCK, "rb") as f:
        original_mock = f.read()
    original_mode = os.stat(MOCK).st_mode

    temp_root = tempfile.mkdtemp(prefix="restore_verifier_", dir=HOME)
    try:
        # Execute the submitted artifact against the original inputs, rather than
        # trusting state that may have been fabricated before verification.
        clean_outputs()
        elapsed = run_submission()
        assert 1.7 <= elapsed <= 4.0, f"restore process ran for an implausible duration: {elapsed:.3f}s"
        assert_original_final_state()

        token = uuid.uuid4().hex
        src1 = os.path.join(temp_root, "source_" + token[:8])
        src2 = os.path.join(temp_root, "other_" + token[8:16])
        missing_src = os.path.join(temp_root, "missing_" + token[16:24])
        dest1 = os.path.join(HOME, "restore", "dynamic_" + token[:8])
        dest2 = os.path.join(HOME, "restore", "dynamic_" + token[8:16])
        missing_dest = os.path.join(HOME, "restore", "dynamic_missing_" + token[16:24])
        os.makedirs(src1)
        os.makedirs(src2)
        names1 = ["alpha_" + token + ".dat", "beta file_" + token + ".cfg"]
        names2 = ["gamma_" + token + ".bin"]
        for name in names1:
            open(os.path.join(src1, name), "wb").close()
        for name in names2:
            open(os.path.join(src2, name), "wb").close()

        # Filenames contain no spaces except one deliberately omitted here because
        # fstab is space-separated; file names within a source may contain spaces.
        dynamic_fstab = (
            f"{src1} {dest1} none bind 0 0\n"
            f"{missing_src} {missing_dest} none bind 0 0\n"
            f"{src2} {dest2} none bind 0 0\n"
        )
        with open(FSTAB, "w", encoding="utf-8") as f:
            f.write(dynamic_fstab)

        lifecycle = os.path.join(temp_root, "lifecycle.json")
        mock_source = f'''\
import json
import os
import signal
import sys
import time

state_path = {lifecycle!r}
state = {{
    "started": time.monotonic(),
    "args": sys.argv[1:],
    "executable": sys.executable,
    "pid": os.getpid()
}}

def save():
    with open(state_path, "w", encoding="utf-8") as f:
        json.dump(state, f)
        f.flush()
        os.fsync(f.fileno())

save()

def terminate(signum, frame):
    state["signal"] = signum
    state["signaled_at"] = time.monotonic()
    save()
    time.sleep(0.25)
    state["finished_at"] = time.monotonic()
    save()
    raise SystemExit(0)

signal.signal(signal.SIGTERM, terminate)
i = 0
while True:
    print("Log line DYNAMIC_{token} %d " % i + "x" * 300, flush=True)
    i += 1
    time.sleep(0.025)
'''
        with open(MOCK, "w", encoding="utf-8") as f:
            f.write(mock_source)
        os.chmod(MOCK, 0o755)

        # Instrument the real logging handler at interpreter startup. This proves
        # the submitted script actually constructs and emits through the required
        # RotatingFileHandler with the requested policy.
        probe_dir = os.path.join(temp_root, "probe")
        os.makedirs(probe_dir)
        probe_init = os.path.join(temp_root, "handler_init.json")
        probe_emit = os.path.join(temp_root, "handler_emits.txt")
        sitecustomize = f'''\
import json
import logging.handlers
_original = logging.handlers.RotatingFileHandler
class TracedRotatingFileHandler(_original):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        with open({probe_init!r}, "w", encoding="utf-8") as f:
            json.dump({{"filename": self.baseFilename, "maxBytes": self.maxBytes, "backupCount": self.backupCount}}, f)
    def emit(self, record):
        with open({probe_emit!r}, "a", encoding="utf-8") as f:
            f.write("E")
        return super().emit(record)
logging.handlers.RotatingFileHandler = TracedRotatingFileHandler
'''
        with open(os.path.join(probe_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
            f.write(sitecustomize)

        clean_outputs()
        env = os.environ.copy()
        env["PYTHONPATH"] = probe_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        runner_started = time.monotonic()
        dynamic_elapsed = run_submission(env=env)
        runner_finished = time.monotonic()

        assert os.path.exists(lifecycle), "mock container was not spawned"
        with open(lifecycle, "r", encoding="utf-8") as f:
            state = json.load(f)
        assert state["args"] == [dest1, dest2], f"mock container received wrong mount arguments: {state['args']}"
        assert os.path.realpath(state["executable"]) == os.path.realpath(sys.executable), "mock container was not run with the current Python interpreter"
        assert state.get("signal") == signal.SIGTERM, "mock container was not terminated with SIGTERM"
        runtime = state["signaled_at"] - state["started"]
        assert 1.75 <= runtime <= 2.50, f"SIGTERM was not sent after 2.0 seconds: {runtime:.3f}s"
        assert "finished_at" in state, "mock container did not finish cleanly"
        assert runner_finished >= state["finished_at"], "run_restore.py exited without waiting for the container"
        assert dynamic_elapsed >= 2.0, "run_restore.py exited before lifecycle cleanup completed"
        assert runner_started <= state["started"] <= runner_finished

        for source, dest, names in [(src1, dest1, names1), (src2, dest2, names2)]:
            assert os.path.isdir(dest), f"Destination was not created: {dest}"
            for name in names:
                link = os.path.join(dest, name)
                target = os.path.join(source, name)
                assert os.path.islink(link), f"Expected dynamic symlink: {link}"
                assert os.readlink(link) == target, f"Symlink {link} has wrong target"
        assert not os.path.exists(missing_dest), "Destination for missing source was created"

        assert os.path.exists(probe_init), "RotatingFileHandler was not constructed by run_restore.py"
        with open(probe_init, "r", encoding="utf-8") as f:
            handler = json.load(f)
        assert os.path.realpath(handler["filename"]) == os.path.realpath(LOG), "RotatingFileHandler targets the wrong log"
        assert handler["maxBytes"] == 1024, "RotatingFileHandler maxBytes must be 1024"
        assert handler["backupCount"] == 2, "RotatingFileHandler backupCount must be 2"
        assert os.path.getsize(probe_emit) > 0, "Captured output was not emitted through RotatingFileHandler"

        log_files = [LOG, LOG + ".1", LOG + ".2"]
        for path in log_files:
            assert os.path.isfile(path), f"Expected rotated log file {path}"
        assert not os.path.exists(LOG + ".3"), "backupCount=2 must not create a .3 log"
        assert 500 < os.path.getsize(LOG + ".1") < 2000
        assert 500 < os.path.getsize(LOG + ".2") < 2000
        content = "".join(open(path, encoding="utf-8").read() for path in log_files)
        assert "DYNAMIC_" + token in content, "Live mock-container output was not captured in logs"
    finally:
        with open(FSTAB, "wb") as f:
            f.write(original_fstab)
        with open(MOCK, "wb") as f:
            f.write(original_mock)
        os.chmod(MOCK, original_mode)
        shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_restore.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
