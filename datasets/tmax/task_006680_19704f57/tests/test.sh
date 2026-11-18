#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import string
import subprocess
import tempfile
import zlib
from pathlib import Path

BASE = Path('/home/user/case_1029')
SRC = BASE / 'src'
TOOL = SRC / 'diag_tool'


def run_tool(path, timeout=3):
    return subprocess.run(
        [str(TOOL), str(path)],
        cwd=str(SRC),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def record(payload):
    return b'DATA' + len(payload).to_bytes(2, 'little') + payload


def output_line(payload):
    crc = zlib.crc32(payload) & 0xffffffff
    return f'Record [{crc:08x}]: {payload.decode("ascii")}\n'.encode()


def test_makefile_fixed_and_builds_real_tool():
    makefile_path = SRC / 'Makefile'
    assert os.path.isfile(makefile_path), f'File {makefile_path} is missing'
    content = makefile_path.read_text()
    assert '-lz' in content, 'Makefile does not link the zlib library (-lz).'

    subprocess.run(['make', 'clean'], cwd=str(SRC), stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, timeout=10, check=True)
    built = subprocess.run(['make'], cwd=str(SRC), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=15, check=False)
    assert built.returncode == 0, built.stderr.decode(errors='replace')
    assert TOOL.is_file(), 'make did not create src/diag_tool.'
    assert os.access(TOOL, os.X_OK), 'src/diag_tool is not executable.'
    assert TOOL.read_bytes()[:4] == b'\x7fELF', 'diag_tool is not a compiled ELF executable.'


def test_parser_handles_derived_records_and_truncation():
    alphabet = string.ascii_letters + string.digits
    payloads = [
        ''.join(secrets.choice(alphabet) for _ in range(19)).encode(),
        ''.join(secrets.choice(alphabet) for _ in range(31)).encode(),
    ]

    with tempfile.TemporaryDirectory() as td:
        valid = Path(td) / (secrets.token_hex(8) + '.bin')
        valid.write_bytes(b''.join(record(p) for p in payloads))
        result = run_tool(valid)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        expected = b''.join(output_line(p) for p in payloads)
        assert result.stdout == expected, (
            f'diag_tool parsed generated records incorrectly.\n'
            f'Expected: {expected!r}\nActual: {result.stdout!r}'
        )

        truncated = Path(td) / (secrets.token_hex(8) + '.bin')
        declared = secrets.randbelow(40) + 8
        partial = ''.join(secrets.choice(alphabet) for _ in range(declared - 3)).encode()
        truncated.write_bytes(b'DATA' + declared.to_bytes(2, 'little') + partial)
        result = run_tool(truncated, timeout=2)
        assert result.returncode == 0, 'diag_tool did not gracefully terminate on a truncated payload.'


def test_parsed_logs():
    logs_path = BASE / 'parsed_logs.txt'
    assert os.path.isfile(logs_path), f'File {logs_path} is missing'
    content = logs_path.read_text(errors='replace')

    assert 'System Bootup' in content, 'parsed_logs.txt is missing the first record.'
    assert 'Service Started' in content, 'parsed_logs.txt is missing the second record.'

    customer = BASE / 'data/customer_events.bin'
    result = run_tool(customer, timeout=2)
    assert result.returncode == 0, 'diag_tool failed while parsing customer_events.bin.'
    assert logs_path.read_bytes() == result.stdout, (
        'parsed_logs.txt is not the standard output produced by the rebuilt diag_tool.'
    )

    raw = customer.read_bytes()
    pos = 0
    complete_payloads = []
    while pos + 6 <= len(raw):
        assert raw[pos:pos + 4] == b'DATA', 'Customer fixture has an invalid record header.'
        length = int.from_bytes(raw[pos + 4:pos + 6], 'little')
        pos += 6
        if pos + length > len(raw):
            break
        complete_payloads.append(raw[pos:pos + length])
        pos += length
    for payload in complete_payloads:
        assert output_line(payload) in result.stdout, f'Missing parsed record {payload!r}.'


def test_db_dump():
    dump_path = BASE / 'db_dump.txt'
    assert os.path.isfile(dump_path), f'File {dump_path} is missing'
    content = dump_path.read_text(errors='replace')

    assert 'Init' in content, 'db_dump.txt is missing row 1.'
    assert 'Disk IO error' in content, 'db_dump.txt is missing row 2 (from WAL).'
    assert 'Emergency shutdown triggered' in content, 'db_dump.txt is missing row 3 (from WAL).'

    db = BASE / 'db/telemetry.db'
    with sqlite3.connect(str(db)) as conn:
        expected = conn.execute('SELECT id, msg FROM diagnostics ORDER BY id').fetchall()

    lines = [line for line in content.splitlines() if line.strip()]
    assert len(lines) == len(expected), (
        f'db_dump.txt must contain all and only the {len(expected)} diagnostics rows.'
    )
    unmatched = lines[:]
    for row_id, msg in expected:
        matches = [line for line in unmatched
                   if msg in line and re.search(rf'(?<!\d){re.escape(str(row_id))}(?!\d)', line)]
        assert matches, f'db_dump.txt is missing diagnostics row ({row_id}, {msg!r}).'
        unmatched.remove(matches[0])
    assert not unmatched, f'db_dump.txt contains unexpected rows: {unmatched!r}'


def build_vulnerable_parser(directory):
    source = Path(directory) / 'vulnerable.c'
    binary = Path(directory) / 'vulnerable'
    source.write_text(r'''#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 2;
    unsigned char header[4];
    if (fread(header, 1, 4, f) < 4) return 0;
    if (memcmp(header, "DATA", 4) != 0) return 0;
    unsigned char lb[2];
    if (fread(lb, 1, 2, f) < 2) return 0;
    unsigned int len = (unsigned int)lb[0] | ((unsigned int)lb[1] << 8);
    char *buf = malloc(len ? len : 1);
    unsigned int left = len;
    char *ptr = buf;
    while (left > 0) {
        size_t r = fread(ptr, 1, left, f);
        left -= r;
        ptr += r;
    }
    free(buf);
    fclose(f);
    return 0;
}
''')
    subprocess.run(['gcc', '-O0', '-o', str(binary), str(source)],
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return binary


def test_mre_generator():
    base_dir = BASE
    mre_bin = base_dir / 'mre.bin'

    if mre_bin.exists():
        mre_bin.unlink()

    scripts = list(base_dir.glob('make_mre.*'))
    assert scripts, 'MRE generator script (e.g., make_mre.py or make_mre.sh) is missing.'
    script_path = scripts[0]

    if script_path.suffix == '.py':
        subprocess.run(['python3', str(script_path)], cwd=str(base_dir), check=True, timeout=5)
    elif script_path.suffix == '.sh':
        subprocess.run(['bash', str(script_path)], cwd=str(base_dir), check=True, timeout=5)
    else:
        subprocess.run([str(script_path)], cwd=str(base_dir), check=True, timeout=5)

    assert mre_bin.exists(), 'MRE generator did not create mre.bin.'
    data = mre_bin.read_bytes()

    assert len(data) >= 6, 'mre.bin is too small to contain a valid header and length.'
    assert data[:4] == b'DATA', "mre.bin does not start with the correct 'DATA' magic bytes."

    expected_len = int.from_bytes(data[4:6], 'little')
    actual_payload_len = len(data) - 6
    assert actual_payload_len < expected_len, (
        f'mre.bin is not truncated. Expected {expected_len} payload bytes, '
        f'but found {actual_payload_len}.'
    )

    # Six bytes (header plus length), a declared one-byte payload, and no payload
    # is the smallest possible single-record file that reaches the vulnerable loop.
    assert data == b'DATA\x01\x00', (
        'mre.bin is not minimal; the minimal reproducer is one DATA header, '
        'a requested length of 1, and zero payload bytes.'
    )

    with tempfile.TemporaryDirectory() as td:
        vulnerable = build_vulnerable_parser(td)
        try:
            subprocess.run([str(vulnerable), str(mre_bin)], stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=0.5, check=False)
        except subprocess.TimeoutExpired:
            pass
        else:
            raise AssertionError('mre.bin does not trigger the original parser infinite loop.')

        # Every proper prefix of this six-byte file must fail before the payload loop.
        for size in range(len(data)):
            prefix = Path(td) / f'prefix-{size}.bin'
            prefix.write_bytes(data[:size])
            subprocess.run([str(vulnerable), str(prefix)], stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=0.5, check=False)

    fixed = run_tool(mre_bin, timeout=2)
    assert fixed.returncode == 0, 'The fixed diag_tool does not terminate cleanly on mre.bin.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
