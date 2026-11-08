#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import errno
import glob
import os
import random
import select
import signal
import stat
import subprocess
import time
import pytest

ARCHIVER = "/home/user/archiver"
SOURCE = "/home/user/archiver.c"
FIFO = "/home/user/stream.fifo"


def rle(data):
    out = bytearray()
    if not data:
        return bytes(out)
    value = data[0]
    count = 1
    for b in data[1:]:
        if b == value and count < 255:
            count += 1
        else:
            out.extend((count, value))
            value = b
            count = 1
    out.extend((count, value))
    return bytes(out)


def make_segment(counts, first_value=None):
    values = []
    for i in range(len(counts)):
        if i == 0 and first_value is not None:
            value = first_value
        elif i == 1:
            value = 0
        elif i == 2:
            value = 255
        else:
            value = os.urandom(1)[0]
        while values and value == values[-1]:
            value = os.urandom(1)[0]
        values.append(value)
    data = b"".join(bytes((value,)) * count for count, value in zip(counts, values))
    return data, values[-1]


def open_fifo_writer(proc, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        assert proc.poll() is None, "Archiver exited prematurely before opening the FIFO."
        try:
            return os.open(FIFO, os.O_WRONLY | os.O_NONBLOCK)
        except OSError as exc:
            if exc.errno not in (errno.ENXIO, errno.ENOENT):
                raise
            time.sleep(0.05)
    pytest.fail("Archiver did not open /home/user/stream.fifo for reading.")


def write_all(fd, data, timeout=5):
    view = memoryview(data)
    deadline = time.monotonic() + timeout
    while view:
        if time.monotonic() >= deadline:
            pytest.fail("Timed out writing generated binary data to the FIFO.")
        try:
            written = os.write(fd, view)
            view = view[written:]
        except BlockingIOError:
            select.select([], [fd], [], 0.05)


def wait_for_exact_file(path, expected, timeout=5):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        if os.path.exists(path):
            with open(path, "rb") as f:
                last = f.read()
            if last == expected:
                return
        time.sleep(0.05)
    got = "missing" if last is None else last.hex()
    pytest.fail(f"{path} content incorrect. Expected {expected.hex()}, got {got}")


def test_archiver_executable_exists():
    assert os.path.exists(ARCHIVER), "/home/user/archiver does not exist"
    assert os.access(ARCHIVER, os.X_OK), "/home/user/archiver is not executable"
    assert os.path.isfile(ARCHIVER), "/home/user/archiver is not a regular file"
    assert os.path.isfile(SOURCE), "/home/user/archiver.c does not exist"
    with open(ARCHIVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/archiver is not a compiled ELF executable"


def test_archiver_behavior():
    subprocess.run(["pkill", "-9", "-f", "/home/user/archiver"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)

    for path in glob.glob("/home/user/repo*.dat"):
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)
    if os.path.lexists(FIFO):
        assert stat.S_ISFIFO(os.stat(FIFO).st_mode), f"{FIFO} exists but is not a FIFO"
    else:
        os.mkfifo(FIFO)

    rng = random.SystemRandom()
    segment1, last1 = make_segment([
        rng.randint(1, 31), rng.randint(256, 760), 255,
        256, rng.randint(2, 90), rng.randint(300, 620)
    ])
    segment2, last2 = make_segment([
        rng.randint(1, 50), rng.randint(510, 900), 1,
        255, rng.randint(256, 520), rng.randint(2, 70)
    ], first_value=last1)
    segment3, _ = make_segment([
        rng.randint(1, 80), 256, rng.randint(257, 850),
        255, rng.randint(2, 100), rng.randint(300, 700)
    ], first_value=last2)

    expected1 = rle(segment1) + b"\x00\x00"
    expected2 = rle(segment2) + b"\x00\x00"
    expected3 = rle(segment3) + b"\x00\x00"

    proc = subprocess.Popen([ARCHIVER])
    fd = None
    try:
        time.sleep(0.2)
        assert proc.poll() is None, "Archiver exited prematurely before receiving any data."
        fd = open_fifo_writer(proc)

        write_all(fd, segment1)
        time.sleep(0.4)
        proc.send_signal(signal.SIGUSR1)
        wait_for_exact_file("/home/user/repo.1.dat", expected1)
        assert proc.poll() is None, "Archiver exited after the first SIGUSR1 rotation."

        write_all(fd, segment2)
        time.sleep(0.4)
        proc.send_signal(signal.SIGUSR1)
        wait_for_exact_file("/home/user/repo.2.dat", expected2)
        assert proc.poll() is None, "Archiver exited after the second SIGUSR1 rotation."

        write_all(fd, segment3)
        time.sleep(0.4)
        proc.send_signal(signal.SIGTERM)
        os.close(fd)
        fd = None
        try:
            return_code = proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            pytest.fail("Archiver did not exit within 5 seconds after receiving SIGTERM.")
        assert return_code == 0, f"Archiver did not exit cleanly after SIGTERM (status {return_code})."

        assert os.path.exists("/home/user/repo.1.dat"), "Rotated file /home/user/repo.1.dat was not created after SIGUSR1."
        assert os.path.exists("/home/user/repo.2.dat"), "Rotated file /home/user/repo.2.dat was not created after the second SIGUSR1."
        assert os.path.exists("/home/user/repo.dat"), "Final file /home/user/repo.dat was not created or kept."
        wait_for_exact_file("/home/user/repo.dat", expected3)

        archive_names = sorted(os.path.basename(p) for p in glob.glob("/home/user/repo*.dat"))
        assert archive_names == ["repo.1.dat", "repo.2.dat", "repo.dat"], \
            f"Unexpected archive rotation files: {archive_names}"
    finally:
        if fd is not None:
            os.close(fd)
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
TEST_EOF

if timeout 40s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
