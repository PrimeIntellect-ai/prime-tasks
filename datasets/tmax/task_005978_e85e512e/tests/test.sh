#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_log_watcher.py
import hashlib
import os
import re
import secrets
import shutil
import signal
import subprocess
import time

SOURCE = "/home/user/log_watcher.cpp"
BINARY = "/home/user/log_watcher"
RAW = "/home/user/raw_logs"
PROCESSED = "/home/user/processed_logs"
MANIFEST = os.path.join(PROCESSED, "manifest.txt")
LATEST = os.path.join(PROCESSED, "latest_error.log")


def clean_dirs():
    os.makedirs(RAW, exist_ok=True)
    os.makedirs(PROCESSED, exist_ok=True)
    for directory in (RAW, PROCESSED):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)


def start_watcher():
    proc = subprocess.Popen(
        [BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    time.sleep(0.4)
    assert proc.poll() is None, "The compiled watcher exited before logs were generated."
    return proc


def stop_watcher(proc):
    if proc.poll() is None:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def wait_for_outputs(names, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        outputs_exist = all(
            os.path.isfile(os.path.join(PROCESSED, name)) for name in names
        )
        if outputs_exist and os.path.isfile(MANIFEST) and os.path.islink(LATEST):
            try:
                lines = open(MANIFEST, encoding="utf-8").read().splitlines()
                if len(lines) >= len(names):
                    return
            except OSError:
                pass
        time.sleep(0.1)
    raise AssertionError("Watcher did not produce all expected outputs in time.")


def expected_manifest(expected):
    return [
        hashlib.sha256(content).hexdigest() + "  " + filename
        for filename, content in expected.items()
    ]


def assert_exact_results(expected, latest_name):
    for filename, content in expected.items():
        path = os.path.join(PROCESSED, filename)
        assert os.path.isfile(path), f"Expected processed log file {path} is missing."
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == content, (
            f"{filename} does not exactly contain the extracted multi-line errors."
        )

    assert os.path.isfile(MANIFEST), f"Manifest file {MANIFEST} is missing."
    with open(MANIFEST, encoding="utf-8") as f:
        manifest_lines = f.read().splitlines()
    assert manifest_lines == expected_manifest(expected), (
        "manifest.txt must contain exactly one correctly formatted checksum line "
        "for each processed output."
    )

    assert os.path.islink(LATEST), f"{LATEST} is missing or is not a symbolic link."
    target = os.readlink(LATEST)
    assert target in (latest_name, os.path.join(PROCESSED, latest_name)), (
        f"Symlink points to {target!r} instead of {latest_name!r}."
    )


def verify_source_and_compile():
    assert os.path.isfile(SOURCE), f"Required C++ source {SOURCE} is missing."
    with open(SOURCE, encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]sys/inotify\.h[>\"]", source), (
        "The watcher source must include the Linux inotify header."
    )
    assert re.search(r"\binotify_init(?:1)?\s*\(", source), (
        "The watcher source does not initialize inotify."
    )
    assert re.search(r"\binotify_add_watch\s*\(", source), (
        "The watcher source does not add an inotify watch."
    )
    assert "IN_MOVED_TO" in source or "IN_CLOSE_WRITE" in source, (
        "The watcher source does not request a completed-file inotify event."
    )

    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, "C++ source failed to compile:\n" + result.stderr
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Compilation did not create an executable watcher."
    )


def run_original_simulation():
    clean_dirs()
    proc = start_watcher()
    try:
        result = subprocess.run(
            ["/home/user/simulate_writer.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, "The provided simulation script failed."
        names = [f"error_app.log.{i}" for i in range(1, 4)]
        wait_for_outputs(names)

        expected = {
            "error_app.log.1": (
                b"[ERROR] Database connection failed\n"
                b"Traceback (most recent call last):\n"
                b"  File \"db.py\", line 12\n"
                b"ConnectionRefusedError\n"
            ),
            "error_app.log.2": (
                b"[ERROR] Out of memory\n"
                b"Allocated: 4GB\n"
                b"Requested: 8GB\n"
            ),
            "error_app.log.3": (
                b"[ERROR] Disk full\n"
                b"Path: /var/log\n"
                b"Free: 0 bytes\n"
                b"Please clear space\n"
            ),
        }
        assert_exact_results(expected, "error_app.log.3")

        # Preserve the original verifier's content assertions explicitly.
        content1 = open(os.path.join(PROCESSED, "error_app.log.1")).read()
        assert "[ERROR] Database connection failed" in content1
        assert "ConnectionRefusedError" in content1
        assert "[INFO]" not in content1
        content2 = open(os.path.join(PROCESSED, "error_app.log.2")).read()
        assert "[ERROR] Out of memory" in content2
        assert "Requested: 8GB" in content2
        assert "[DEBUG]" not in content2
        content3 = open(os.path.join(PROCESSED, "error_app.log.3")).read()
        assert "[ERROR] Disk full" in content3
        assert "Please clear space" in content3
        assert "[WARN]" not in content3
    finally:
        stop_watcher(proc)


def run_unpredictable_simulation():
    clean_dirs()
    numbers = sorted(secrets.SystemRandom().sample(range(20, 900), 3))
    token = secrets.token_hex(12)

    raw_contents = [
        (
            f"[INFO] begin-{token}\n"
            f"[ERROR] first-{token}\n"
            f"detail one {token}\n"
            f"detail two {numbers[0]}\n"
            f"[DEBUG] ignored-{token}\n"
        ).encode(),
        (
            f"[WARN] no-error-{token}\n"
            f"continuation {numbers[1]}\n"
            f"[INFO] still-normal\n"
        ).encode(),
        (
            f"[ERROR] alpha-{token}\n"
            f"alpha detail\n"
            f"[INFO] separator\n"
            f"[ERROR] beta-{token}\n"
            f"beta detail {numbers[2]}\n"
        ).encode(),
    ]
    extracted = [
        (
            f"[ERROR] first-{token}\n"
            f"detail one {token}\n"
            f"detail two {numbers[0]}\n"
        ).encode(),
        b"",
        (
            f"[ERROR] alpha-{token}\n"
            f"alpha detail\n"
            f"[ERROR] beta-{token}\n"
            f"beta detail {numbers[2]}\n"
        ).encode(),
    ]

    expected = {
        f"error_app.log.{number}": content
        for number, content in zip(numbers, extracted)
    }

    proc = start_watcher()
    try:
        for number, content in zip(numbers, raw_contents):
            active = os.path.join(RAW, "app.log")
            with open(active, "wb") as f:
                f.write(content)
                f.flush()
                os.fsync(f.fileno())
            os.rename(active, os.path.join(RAW, f"app.log.{number}"))
            time.sleep(0.25)

        names = list(expected.keys())
        wait_for_outputs(names)
        assert proc.poll() is None, "Watcher stopped while processing rotated logs."
        assert_exact_results(expected, names[-1])
    finally:
        stop_watcher(proc)


verify_source_and_compile()
run_original_simulation()
run_unpredictable_simulation()
PY_EOF

if python3 /tmp/verify_log_watcher.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
