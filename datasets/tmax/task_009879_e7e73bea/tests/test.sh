#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_healthcheck.py
import os
import shutil
import socket
import subprocess
import uuid

SOURCE = "/home/user/bin/healthcheck.c"
EXECUTABLE = "/home/user/bin/healthcheck"
POOL = "/home/user/pool"
PORTS = "/home/user/ports"


def test_01_source_file_exists():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."


def test_02_executable_exists_and_executable():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", f"File {EXECUTABLE} is not a compiled executable."


def test_03_initial_pool_was_cleaned():
    # The setup started no listeners, so the required initial run should have
    # removed every original backend symlink.
    for link_name in ("srv1", "srv2", "srv3", "srv4"):
        link_path = os.path.join(POOL, link_name)
        assert not os.path.lexists(link_path), (
            f"Symlink {link_path} should have been removed because its port was closed."
        )


def _clear_pool():
    for entry in os.scandir(POOL):
        if entry.is_dir(follow_symlinks=False):
            shutil.rmtree(entry.path)
        else:
            os.unlink(entry.path)


def test_04_dynamic_pool_behavior():
    _clear_pool()
    token = uuid.uuid4().hex
    open_sockets = []
    closed_reservations = []
    target_paths = []
    link_paths = []
    regular_path = os.path.join(POOL, f"ordinary_{token}")

    try:
        open_ports = []
        for _ in range(2):
            listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", 0))
            listener.listen(4)
            open_sockets.append(listener)
            open_ports.append(listener.getsockname()[1])

        closed_ports = []
        for _ in range(2):
            # Keeping a TCP socket bound but not listening reserves the random
            # port while ensuring connection attempts are refused.
            reservation = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            reservation.bind(("127.0.0.1", 0))
            closed_reservations.append(reservation)
            closed_ports.append(reservation.getsockname()[1])

        cases = []
        for index, (port, should_survive) in enumerate(
            [(open_ports[0], True), (closed_ports[0], False),
             (open_ports[1], True), (closed_ports[1], False)]
        ):
            target = os.path.join(PORTS, f"dynamic_{token}_{index}.txt")
            link = os.path.join(POOL, f"backend_{token}_{index}")
            with open(target, "w", encoding="ascii") as port_file:
                port_file.write(f"{port}\n")
            os.symlink(target, link)
            target_paths.append(target)
            link_paths.append(link)
            cases.append((link, should_survive))

        # A non-symlink is not a backend entry and must not be unlinked.
        with open(regular_path, "w", encoding="ascii") as regular_file:
            regular_file.write(f"{closed_ports[0]}\n")

        subprocess.run(
            [EXECUTABLE],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )

        for link, should_survive in cases:
            if should_survive:
                assert os.path.islink(link), f"Healthy backend symlink {link} was removed."
            else:
                assert not os.path.lexists(link), f"Dead backend symlink {link} was retained."

        assert os.path.isfile(regular_path), "The health checker removed a non-symlink pool item."
        for target in target_paths:
            assert os.path.isfile(target), f"The target port file {target} was removed."
    finally:
        for sock in open_sockets + closed_reservations:
            sock.close()
        for path in link_paths + [regular_path]:
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
        for path in target_paths:
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_healthcheck.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
