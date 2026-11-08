#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import itertools
import os
import re
import subprocess
from scapy.all import rdpcap, Raw

HOME = '/home/user'
PCAP = os.path.join(HOME, 'traffic.pcap')
MIN_CRASH = os.path.join(HOME, 'min_crash.txt')
DB_RECOVER = os.path.join(HOME, 'db_recover')

ORIGINAL_COMMANDS = [
    'TX 5 BEGIN',
    'TX 5 WRITE A',
    'TX 2 BEGIN',
    'TX 2 WRITE B',
    'TX 5 ABORT',
    'TX 3 BEGIN',
    'TX 2 WRITE C',
    'TX 5 ABORT',
    'TX 2 COMMIT',
    'TX 3 COMMIT',
]


def extract_tx_commands(path):
    commands = []
    for packet in rdpcap(path):
        if Raw not in packet:
            continue
        payload = bytes(packet[Raw].load).decode('utf-8', errors='strict')
        for line in payload.splitlines():
            if line.startswith('TX '):
                commands.append(line)
    return commands


def triggers_original_double_finalize(commands):
    # Model the supplied vulnerable implementation: a successful finalization
    # frees a transaction but leaves a dangling non-NULL table entry. A later
    # ABORT/COMMIT of that entry performs the crashing second free.
    states = {}
    for command in commands:
        match = re.match(r'^TX\s+(-?\d+)\s+(\S+)', command)
        if not match:
            continue
        txid = int(match.group(1))
        action = match.group(2)
        if txid < 0 or txid >= 100:
            continue
        state = states.get(txid, 'absent')
        if action == 'BEGIN':
            if state == 'absent':
                states[txid] = 'active'
        elif action in ('ABORT', 'COMMIT'):
            if state == 'active':
                states[txid] = 'dangling'
            elif state == 'dangling':
                return True
    return False


def derive_absolute_minima(commands):
    for size in range(1, len(commands) + 1):
        minima = []
        for indexes in itertools.combinations(range(len(commands)), size):
            candidate = tuple(commands[i] for i in indexes)
            if triggers_original_double_finalize(candidate):
                minima.append(candidate)
        if minima:
            return minima
    return []


def read_nonempty_lines(path):
    with open(path, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]


def run_binary(data):
    return subprocess.run(
        [DB_RECOVER], input=data.encode('utf-8'), cwd=HOME,
        capture_output=True, timeout=5
    )


def test_min_crash_file():
    assert os.path.isfile(MIN_CRASH), f'{MIN_CRASH} does not exist'
    lines = read_nonempty_lines(MIN_CRASH)

    # Preserve the original format and structural assertions.
    assert len(lines) == 3, 'min_crash.txt should contain exactly 3 lines'
    pattern = re.compile(r'^TX\s+(\d+)\s+([A-Z]+)$')
    match1 = pattern.match(lines[0])
    assert match1, "Line 1 does not match expected format 'TX <id> ACTION'"
    id1, action1 = match1.groups()
    assert action1 == 'BEGIN', 'First command must be BEGIN'
    match2 = pattern.match(lines[1])
    assert match2, "Line 2 does not match expected format 'TX <id> ACTION'"
    id2, action2 = match2.groups()
    assert action2 in ('ABORT', 'COMMIT'), 'Second command must be ABORT or COMMIT'
    match3 = pattern.match(lines[2])
    assert match3, "Line 3 does not match expected format 'TX <id> ACTION'"
    id3, action3 = match3.groups()
    assert action3 in ('ABORT', 'COMMIT'), 'Third command must be ABORT or COMMIT'
    assert id1 == id2 == id3, 'Transaction IDs must be identical across all three lines'

    # Derive the minimum from the packet payloads rather than trusting the file.
    captured = extract_tx_commands(PCAP)
    assert captured == ORIGINAL_COMMANDS, 'traffic.pcap was altered or does not contain the supplied capture'
    minima = derive_absolute_minima(captured)
    assert minima, 'No crashing sequence could be derived from traffic.pcap'
    assert tuple(lines) in minima, 'min_crash.txt is not an absolute minimum crashing subsequence of traffic.pcap'
    assert all(len(candidate) == len(lines) for candidate in minima)


def test_recover_fixed_and_compiled():
    # Preserve the original clean rebuild and executable checks.
    subprocess.run(['make', 'clean'], cwd=HOME, capture_output=True)
    make_build = subprocess.run(['make'], cwd=HOME, capture_output=True)
    assert make_build.returncode == 0, 'Failed to compile db_recover'
    assert os.path.isfile(DB_RECOVER), 'db_recover executable not found after make'
    assert os.access(DB_RECOVER, os.X_OK), 'db_recover is not executable'

    crash_data = open(MIN_CRASH, 'r', encoding='utf-8').read()
    run_min_crash = run_binary(crash_data)
    assert run_min_crash.returncode == 0, 'db_recover crashed or returned non-zero when processing min_crash.txt'

    test_sequence = 'TX 99 BEGIN\nTX 99 COMMIT\nTX 99 ABORT\n'
    run_test_seq = run_binary(test_sequence)
    assert run_test_seq.returncode == 0, 'db_recover crashed on a double-free sequence, bug is not fully fixed'

    # Exercise varied recovery/error paths using IDs derived at verification time.
    seed = hashlib.sha256(open(PCAP, 'rb').read()).digest()
    ids = sorted({10 + (byte % 80) for byte in seed[:8]})
    dynamic = []
    for txid in ids:
        dynamic.extend([
            f'TX {txid} COMMIT',       # finalize before BEGIN
            f'TX {txid} BEGIN',
            f'TX {txid} WRITE value',
            f'TX {txid} ABORT',
            f'TX {txid} ABORT',        # repeated finalization
            f'TX {txid} BEGIN',         # ID must be reusable
            f'TX {txid} COMMIT',
        ])
    dynamic.extend(['TX -1 BEGIN', 'TX 100 BEGIN', 'not a command', 'TX 1 UNKNOWN'])
    result = run_binary('\n'.join(dynamic) + '\n')
    assert result.returncode == 0, 'db_recover failed recovery or invalid-transition handling'


def test_recovery_logic_is_not_a_noop():
    # Include the submitted source in a small white-box harness. This checks the
    # existing recovery semantics and, crucially, that finalization clears the
    # table entry; an executable that simply returns zero cannot pass.
    captured = extract_tx_commands(PCAP)
    probe_id = 10 + (hashlib.sha256('\n'.join(captured).encode()).digest()[0] % 80)
    harness = r'''
#include <assert.h>
#include <string.h>
#define main submitted_program_main
#include "/home/user/recover.c"
#undef main

int main(void) {
    char begin1[] = "TX __ID__ BEGIN";
    char begin2[] = "TX __ID__ BEGIN";
    char write1[] = "TX __ID__ WRITE payload";
    char commit1[] = "TX __ID__ COMMIT";
    char abort1[] = "TX __ID__ ABORT";

    assert(tx_table[__ID__] == NULL);
    process_command(abort1);
    assert(tx_table[__ID__] == NULL);

    process_command(begin1);
    assert(tx_table[__ID__] != NULL);
    assert(tx_table[__ID__]->id == __ID__);
    assert(tx_table[__ID__]->active == 1);
    Transaction *first = tx_table[__ID__];

    process_command(begin2);
    assert(tx_table[__ID__] == first);
    process_command(write1);
    assert(tx_table[__ID__] != NULL);
    assert(strcmp(tx_table[__ID__]->data, "data") == 0);

    process_command(commit1);
    assert(tx_table[__ID__] == NULL);
    process_command(abort1);
    assert(tx_table[__ID__] == NULL);

    process_command(begin1);
    assert(tx_table[__ID__] != NULL);
    process_command(abort1);
    assert(tx_table[__ID__] == NULL);
    return 0;
}
'''.replace('__ID__', str(probe_id))

    harness_path = '/tmp/recovery_harness.c'
    binary_path = '/tmp/recovery_harness'
    with open(harness_path, 'w', encoding='utf-8') as f:
        f.write(harness)
    build = subprocess.run(
        ['gcc', '-g', '-O0', harness_path, '-o', binary_path],
        capture_output=True, timeout=10
    )
    assert build.returncode == 0, 'recover.c could not be tested as recovery logic: ' + build.stderr.decode(errors='replace')
    run = subprocess.run([binary_path], capture_output=True, timeout=5)
    assert run.returncode == 0, 'recover.c does not preserve transaction processing and safely clear finalized entries'
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
