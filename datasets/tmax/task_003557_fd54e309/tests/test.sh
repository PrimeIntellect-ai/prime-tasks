#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_process_logs.py
import ctypes
import itertools
import os
import pathlib
import secrets
import shutil
import struct
import subprocess
import sys

HOME = pathlib.Path('/home/user')
LOGS = HOME / 'logs'
ARCHIVE = HOME / 'archive'
SOURCE = HOME / 'process_logs.cpp'
SUMMARY = HOME / 'critical_summary.txt'
TMP = HOME / 'critical_summary.tmp'

node1 = b'''[INFO] 2023-10-01 10:00:00
System started up successfully.
Checking disk quotas...
[WARN] 2023-10-01 10:05:00
Latency spike detected on volume A.
[CRITICAL] 2023-10-01 10:10:00
Disk space critically low on /dev/sda1
Immediate action required.
Dumping core state...
[INFO] 2023-10-01 10:15:00
Cleanup routine started.
'''
node2 = b'''[INFO] 2023-10-01 09:00:00
Node 2 initialized.
[CRITICAL] 2023-10-01 09:30:00
RAID array degraded!
Drive 3 failed.
Please replace drive 3 and rebuild.
[WARN] 2023-10-01 09:35:00
Rebuild pending admin approval.
'''

block_node1 = '''[CRITICAL] 2023-10-01 10:10:00
Disk space critically low on /dev/sda1
Immediate action required.
Dumping core state...'''
block_node2 = '''[CRITICAL] 2023-10-01 09:30:00
RAID array degraded!
Drive 3 failed.
Please replace drive 3 and rebuild.'''


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def check_original_final_state():
    require(not TMP.exists(), '/home/user/critical_summary.tmp should not exist')
    require(SUMMARY.is_file(), '/home/user/critical_summary.txt must exist')
    content = SUMMARY.read_text().strip()
    option1 = block_node1 + '\n' + block_node2
    option2 = block_node2 + '\n' + block_node1
    require(content in (option1, option2), 'critical_summary.txt does not contain exactly the expected records')
    require('[INFO]' not in content, '[INFO] tag found in critical_summary.txt')
    require('[WARN]' not in content, '[WARN] tag found in critical_summary.txt')

    if LOGS.is_dir():
        remaining = [p.name for p in LOGS.iterdir() if p.name.endswith('.log')]
        require(not remaining, 'Found .log files left in /home/user/logs: ' + repr(remaining))

    archived1 = ARCHIVE / 'node1.archived'
    archived2 = ARCHIVE / 'node2.archived'
    require(archived1.is_file(), '/home/user/archive/node1.archived does not exist')
    require(archived2.is_file(), '/home/user/archive/node2.archived does not exist')
    require(archived1.read_bytes() == node1, 'node1.archived does not preserve the original node1.log contents')
    require(archived2.read_bytes() == node2, 'node2.archived does not preserve the original node2.log contents')


def compile_submission():
    require(SOURCE.is_file(), '/home/user/process_logs.cpp must exist and be a regular file')
    result = subprocess.run(
        ['g++', '-std=c++17', '-O2', str(SOURCE), '-o', '/tmp/process_logs_verified'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    require(result.returncode == 0, 'process_logs.cpp did not compile:\n' + result.stderr)


def dynamic_execution_test():
    token = secrets.token_hex(12)
    names = [f'alpha_{token}.log', f'beta_{token}.log', f'gamma_{token}.log']
    critical = [
        f'''[CRITICAL] {token}-A
first critical line {token}
continuation A
[with brackets but not a severity record]''',
        f'''[CRITICAL] {token}-B
second critical line
continuation B {token}''',
        f'''[CRITICAL] {token}-C
final critical record {token}
last continuation'''
    ]
    inputs = {
        names[0]: (f'''[INFO] start-{token}
ordinary alpha line
{critical[0]}
[WARN] after-alpha
warning detail
''').encode(),
        names[1]: (f'''[WARN] begin-{token}
warning body
{critical[1]}
[INFO] after-beta
ordinary body
''').encode(),
        names[2]: (f'''[INFO] gamma-start
ordinary gamma
{critical[2]}
''').encode(),
    }

    if LOGS.exists():
        shutil.rmtree(LOGS)
    LOGS.mkdir(parents=True)
    for name, data in inputs.items():
        (LOGS / name).write_bytes(data)
    (LOGS / f'ignored_{token}.txt').write_text('[CRITICAL] must not be processed\n')
    if SUMMARY.exists():
        SUMMARY.unlink()
    if TMP.exists():
        TMP.unlink()

    libc = ctypes.CDLL(None, use_errno=True)
    inotify_init1 = libc.inotify_init1
    inotify_init1.argtypes = [ctypes.c_int]
    inotify_init1.restype = ctypes.c_int
    inotify_add_watch = libc.inotify_add_watch
    inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    inotify_add_watch.restype = ctypes.c_int

    fd = inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    require(fd >= 0, 'could not initialize rename monitoring')
    watch = inotify_add_watch(fd, b'/home/user', 0x00000040 | 0x00000080)
    require(watch >= 0, 'could not monitor /home/user for atomic rename')

    try:
        result = subprocess.run(['/tmp/process_logs_verified'], cwd='/home/user',
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=30)
        require(result.returncode == 0,
                'compiled process_logs program failed when executed:\n' + result.stderr)

        raw = b''
        while True:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw += chunk
            except BlockingIOError:
                break
    finally:
        os.close(fd)

    moved_from = []
    moved_to = []
    offset = 0
    while offset + 16 <= len(raw):
        wd, mask, cookie, name_len = struct.unpack_from('iIII', raw, offset)
        offset += 16
        name = raw[offset:offset + name_len].split(b'\0', 1)[0].decode(errors='replace')
        offset += name_len
        if mask & 0x00000040:
            moved_from.append((cookie, name))
        if mask & 0x00000080:
            moved_to.append((cookie, name))

    rename_seen = any(
        cookie != 0 and old_name == 'critical_summary.tmp' and
        any(new_cookie == cookie and new_name == 'critical_summary.txt'
            for new_cookie, new_name in moved_to)
        for cookie, old_name in moved_from)
    require(rename_seen, 'program did not atomically rename critical_summary.tmp to critical_summary.txt')
    require(not TMP.exists(), 'temporary summary remained after execution')
    require(SUMMARY.is_file(), 'executed program did not create critical_summary.txt')

    actual = SUMMARY.read_text().strip()
    expected = {'\n'.join(order) for order in itertools.permutations(critical)}
    require(actual in expected, 'executed program failed randomized multi-line CRITICAL extraction')
    require(token in actual, 'randomized records were not processed')
    require('[INFO]' not in actual and '[WARN]' not in actual,
            'non-critical records leaked into randomized summary')

    for name, data in inputs.items():
        path = LOGS / name
        require(path.is_file(), 'the C++ extraction program must leave input logs for the later shell move')
        require(path.read_bytes() == data, 'the C++ program modified an input log')


try:
    check_original_final_state()
    compile_submission()
    dynamic_execution_test()
except Exception as exc:
    print(f'VERIFICATION FAILED: {exc}', file=sys.stderr)
    sys.exit(1)
PY_EOF

if python3 /tmp/verify_process_logs.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
