#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import subprocess
import threading
from pathlib import Path

CPP = Path('/home/user/tcp_checker.cpp')
SCRIPT = Path('/home/user/check_mount_conn.sh')
FSTAB = Path('/home/user/config/micro_fstab')
LOG = Path('/home/user/mount_status.log')
EXE = Path('/home/user/tcp_checker')


def run(cmd, timeout=20):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=timeout)


def listener(port=0):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('127.0.0.1', port))
    sock.listen(2)
    sock.settimeout(15)
    accepted = threading.Event()

    def accept_one():
        try:
            conn, _ = sock.accept()
            accepted.set()
            conn.close()
        except OSError:
            pass

    thread = threading.Thread(target=accept_one, daemon=True)
    thread.start()
    return sock, sock.getsockname()[1], accepted, thread


def unused_port():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def clear_log():
    try:
        LOG.unlink()
    except FileNotFoundError:
        pass


def log_text():
    return LOG.read_text() if LOG.exists() else ''


def assert_elf_executable():
    assert EXE.is_file(), f'Compiled executable {EXE} does not exist.'
    assert os.access(EXE, os.X_OK), f'{EXE} is not executable.'
    assert EXE.read_bytes()[:4] == b'\x7fELF', f'{EXE} is not a compiled ELF executable.'


def test_complete_solution():
    # Preserve the original verifier's source assertions.
    assert CPP.is_file(), f'{CPP} does not exist.'
    original_cpp = CPP.read_bytes()
    assert 'main' in original_cpp.decode(errors='replace'), \
        f'{CPP} does not seem to contain a valid C++ program.'

    assert SCRIPT.is_file(), f'{SCRIPT} does not exist.'
    shell_content = SCRIPT.read_text()
    assert 'tcp_checker' in shell_content, \
        f'{SCRIPT} does not seem to reference tcp_checker.'

    old_fstab = FSTAB.read_bytes() if FSTAB.exists() else None
    old_log = LOG.read_bytes() if LOG.exists() else None
    FSTAB.parent.mkdir(parents=True, exist_ok=True)

    try:
        # Run the submitted script for the original configured success case.
        FSTAB.write_text('cache_node 192.168.1.10 6379 memcache defaults\n'
                         'storage_node 127.0.0.1 8123 nfs ro,noauto\n')
        clear_log()
        fallback = None
        try:
            fallback = listener(8123)
        except OSError:
            # The image's supplied listener already owns this port.
            pass
        result = run(['bash', str(SCRIPT)])
        if fallback:
            fallback[0].close()
        assert result.returncode == 0, result.stderr

        # Preserve the original verifier's exact log assertion.
        assert LOG.is_file(), f'{LOG} does not exist. The script may not have run successfully.'
        lines = [line.strip() for line in LOG.read_text().splitlines() if line.strip()]
        assert len(lines) > 0, f'{LOG} is empty.'
        expected = 'MOUNT_READY: storage_node at 127.0.0.1:8123'
        assert lines[-1] == expected, \
            f"Expected the last log entry to be '{expected}', but got '{lines[-1]}'."

        # Preserve and strengthen the original executable assertions.
        assert_elf_executable()

        # Exercise the submitted C++ checker directly on derived live and closed ports.
        sock, port, accepted, thread = listener()
        result = run([str(EXE), '127.0.0.1', str(port)])
        thread.join(2)
        sock.close()
        assert result.returncode == 0, 'checker did not return 0 for a real TCP listener'
        assert accepted.is_set(), 'checker did not establish a TCP connection'

        port = unused_port()
        result = run([str(EXE), '127.0.0.1', str(port)])
        assert result.returncode == 1, 'checker must return 1 when connection is refused'
        assert run([str(EXE)]).returncode == 1, 'checker must reject missing arguments with status 1'
        assert run([str(EXE), '127.0.0.1']).returncode == 1, \
            'checker must reject a single argument with status 1'

        sock, port, accepted, thread = listener()
        result = run([str(EXE), '127.0.0.1', str(port), 'extra'])
        sock.close()
        thread.join(1)
        assert result.returncode == 1, 'checker must reject extra arguments with status 1'
        assert not accepted.is_set(), 'checker connected despite receiving extra arguments'
        assert run([str(EXE), 'not-an-ip', '1234']).returncode == 1, \
            'checker must return 1 for an invalid IP address'
        assert run([str(EXE), '127.0.0.1', 'not-a-port']).returncode == 1, \
            'checker must return 1 for an invalid port'

        # Missing fstab must be handled before normal connection processing.
        FSTAB.unlink()
        clear_log()
        result = run(['bash', str(SCRIPT)])
        assert result.returncode == 1
        assert log_text() == 'ERROR: fstab missing\n'

        # Use an instrumented, valid checker source to prove that the script compiles
        # the requested source and executes the resulting binary with parsed values.
        marker = Path('/tmp/verifier_checker_args')
        marker.unlink(missing_ok=True)
        probe_source = r'''#include <arpa/inet.h>
#include <fstream>
#include <sys/socket.h>
#include <unistd.h>
#include <cstdlib>
int main(int argc, char **argv) {
    if (argc != 3) return 1;
    std::ofstream f("/tmp/verifier_checker_args");
    f << argv[1] << "\\n" << argv[2] << "\\n";
    char *end = nullptr;
    long p = std::strtol(argv[2], &end, 10);
    if (!end || *end || p < 1 || p > 65535) return 1;
    sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons((unsigned short)p);
    if (inet_pton(AF_INET, argv[1], &a.sin_addr) != 1) return 1;
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return 1;
    int rc = connect(s, reinterpret_cast<sockaddr*>(&a), sizeof(a));
    close(s);
    return rc == 0 ? 0 : 1;
}
'''
        CPP.write_text(probe_source)
        EXE.unlink(missing_ok=True)
        sock, port, accepted, thread = listener()
        FSTAB.write_text('# custom fstab\n'
                         'storage_node_backup 10.0.0.1 1 nfs defaults\n'
                         f'cache_node 127.0.0.1 2 cache defaults\n'
                         f'storage_node\t127.0.0.1\t{port}\tnfs\tro,noauto\n')
        clear_log()
        result = run(['bash', str(SCRIPT)])
        thread.join(2)
        sock.close()
        assert result.returncode == 0, result.stderr
        assert accepted.is_set(), 'script did not cause the compiled checker to connect'
        assert marker.read_text() == f'127.0.0.1\\n{port}\\n', \
            'script did not execute tcp_checker with the parsed IP and port'
        assert log_text() == f'MOUNT_READY: storage_node at 127.0.0.1:{port}\n'
        assert_elf_executable()

        # Restore the submitted checker and test the script's connection-failure path.
        CPP.write_bytes(original_cpp)
        EXE.unlink(missing_ok=True)
        port = unused_port()
        FSTAB.write_text(f'cache_node 127.0.0.1 1 cache defaults\n'
                         f'storage_node 127.0.0.1 {port} nfs defaults\n')
        clear_log()
        result = run(['bash', str(SCRIPT)])
        assert result.returncode == 1
        assert log_text() == 'ERROR: Connection failed for storage_node\n'

        # A missing storage_node entry must fail gracefully rather than report success.
        FSTAB.write_text('cache_node 127.0.0.1 1234 cache defaults\n')
        clear_log()
        result = run(['bash', str(SCRIPT)])
        assert result.returncode != 0
        assert not any(line.startswith('MOUNT_READY:') for line in log_text().splitlines())

        # Compilation errors must not run a stale executable or report readiness.
        CPP.write_text('this is not valid C++\n')
        EXE.unlink(missing_ok=True)
        FSTAB.write_text('storage_node 127.0.0.1 9 nfs defaults\n')
        clear_log()
        result = run(['bash', str(SCRIPT)])
        assert result.returncode != 0
        assert not EXE.exists(), 'script used or created an executable despite compilation failure'
        assert not any(line.startswith('MOUNT_READY:') for line in log_text().splitlines())

    finally:
        CPP.write_bytes(original_cpp)
        if old_fstab is None:
            FSTAB.unlink(missing_ok=True)
        else:
            FSTAB.write_bytes(old_fstab)
        if old_log is None:
            LOG.unlink(missing_ok=True)
        else:
            LOG.write_bytes(old_log)
        # Leave a genuine executable corresponding to the restored submitted source.
        subprocess.run(['g++', str(CPP), '-o', str(EXE)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
