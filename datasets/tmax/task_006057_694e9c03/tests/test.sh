#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import struct
import subprocess
import xml.etree.ElementTree as ET
import pytest

QUOTAS_PATH = '/home/user/quotas.csv'
WAL_PATH = '/home/user/allocations.wal'
XML_PATH = '/home/user/violations.xml'
SOURCE_PATH = '/home/user/check_quotas.c'
EXECUTABLE_PATH = '/home/user/check_quotas'

ORIGINAL_QUOTAS = b'101,1000\n102,2000\n103,500\n104,3000\n'
ORIGINAL_RECORDS = [
    (1600000000, 101, 500),
    (1600000010, 102, 1000),
    (1600000020, 101, 600),
    (1600000030, 103, 200),
    (1600000040, 104, 3000),
    (1600000050, 101, -50),
    (1600000060, 102, 500),
    (1600000070, 103, 400),
    (1600000080, 104, -100),
]
ORIGINAL_WAL = b''.join(struct.pack('<QIi', *record) for record in ORIGINAL_RECORDS)


def get_expected_violations():
    quotas = {}
    if os.path.exists(QUOTAS_PATH):
        with open(QUOTAS_PATH, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    parts = line.split(',')
                    if len(parts) == 2:
                        try:
                            uid = int(parts[0])
                            quota = int(parts[1])
                            quotas[uid] = quota
                        except ValueError:
                            pass

    usage = {}
    if os.path.exists(WAL_PATH):
        with open(WAL_PATH, 'rb') as f:
            while True:
                record = f.read(16)
                if not record or len(record) < 16:
                    break
                ts, uid, delta = struct.unpack('<QIi', record)
                usage[uid] = usage.get(uid, 0) + delta

    violations = []
    for uid, used in usage.items():
        if uid in quotas and used > quotas[uid]:
            violations.append((uid, used, quotas[uid]))
    violations.sort(key=lambda x: x[0])
    return violations


def parse_violations(path):
    assert os.path.isfile(path), f'Expected output file {path} does not exist.'
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        pytest.fail(f'Failed to parse {path} as XML: {e}')

    root = tree.getroot()
    assert root.tag == 'violations', f'Root element should be <violations>, got <{root.tag}>'

    actual = []
    for child in root:
        assert child.tag == 'violation', f'Expected <violation> tag, got <{child.tag}>'
        try:
            uid = int(child.attrib.get('user_id', -1))
            used = int(child.attrib.get('used', -1))
            quota = int(child.attrib.get('quota', -1))
        except ValueError:
            pytest.fail(f'Invalid attribute values in violation tag: {child.attrib}')
        actual.append((uid, used, quota))
    return actual


def derive_expected(quotas, records):
    usage = {}
    for _timestamp, uid, delta in records:
        usage[uid] = usage.get(uid, 0) + delta
    return sorted(
        (uid, used, quotas[uid])
        for uid, used in usage.items()
        if uid in quotas and used > quotas[uid]
    )


def make_case(rng, case_number):
    uids = rng.sample(range(10000, 4000000000), 6)
    quotas = {uid: rng.randint(500, 200000) for uid in uids}
    unknown_uid = rng.choice([x for x in range(4000000001, 4294967295) if x not in quotas])
    timestamp = rng.randint(1, 2**50)
    records = []

    q = quotas[uids[0]]
    records.extend([(timestamp + 1, uids[0], q // 2),
                    (timestamp + 2, uids[0], q - q // 2 + 17 + case_number)])

    q = quotas[uids[1]]
    records.extend([(timestamp + 3, uids[1], q + 91),
                    (timestamp + 4, uids[1], -91)])

    q = quotas[uids[2]]
    records.extend([(timestamp + 5, uids[2], q + 500),
                    (timestamp + 6, uids[2], -200)])

    q = quotas[uids[3]]
    records.extend([(timestamp + 7, uids[3], q // 3),
                    (timestamp + 8, uids[3], -(q // 4))])

    records.extend([(timestamp + 9, uids[4], -123),
                    (timestamp + 10, unknown_uid, 2000000000)])
    rng.shuffle(records)
    quota_items = list(quotas.items())
    rng.shuffle(quota_items)
    quota_bytes = ''.join(f'{uid},{quota}\n' for uid, quota in quota_items).encode()
    wal_bytes = b''.join(struct.pack('<QIi', *record) for record in records)
    return quota_bytes, wal_bytes, derive_expected(quotas, records)


def test_original_inputs_are_intact():
    assert os.path.isfile(QUOTAS_PATH), f'Input file {QUOTAS_PATH} is missing.'
    assert os.path.isfile(WAL_PATH), f'Input file {WAL_PATH} is missing.'
    with open(QUOTAS_PATH, 'rb') as f:
        assert f.read() == ORIGINAL_QUOTAS, 'quotas.csv was modified from the supplied input.'
    with open(WAL_PATH, 'rb') as f:
        assert f.read() == ORIGINAL_WAL, 'allocations.wal was modified from the supplied input.'


def test_violations_xml_exists():
    assert os.path.isfile(XML_PATH), f'Expected output file {XML_PATH} does not exist.'


def test_violations_xml_content():
    assert os.path.isfile(XML_PATH), f'Cannot test content, {XML_PATH} is missing.'
    expected_violations = get_expected_violations()
    actual_violations = parse_violations(XML_PATH)

    assert len(actual_violations) == len(expected_violations), \
        f'Expected {len(expected_violations)} violations, found {len(actual_violations)}.'
    for i, (expected, actual) in enumerate(zip(expected_violations, actual_violations)):
        assert expected == actual, \
            f'Violation mismatch at index {i}. Expected (user_id={expected[0]}, used={expected[1]}, quota={expected[2]}), got (user_id={actual[0]}, used={actual[1]}, quota={actual[2]}).'


def test_c_source_and_executable_exist():
    assert os.path.isfile(SOURCE_PATH), f'C source file {SOURCE_PATH} is missing.'
    assert os.path.isfile(EXECUTABLE_PATH), f'Compiled executable {EXECUTABLE_PATH} is missing.'
    assert os.access(EXECUTABLE_PATH, os.X_OK), f'File {EXECUTABLE_PATH} is not executable.'
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), 'C source must be a regular file.'
    assert stat.S_ISREG(os.lstat(EXECUTABLE_PATH).st_mode), 'Compiled executable must be a regular file.'
    with open(EXECUTABLE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Compiled executable is not an ELF binary.'


def test_program_processes_wal_inputs():
    rebuilt = '/tmp/check_quotas_rebuilt'
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', SOURCE_PATH, '-o', rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, \
        f'Failed to compile submitted C source:\n{compile_result.stderr}'

    with open(QUOTAS_PATH, 'rb') as f:
        saved_quotas = f.read()
    with open(WAL_PATH, 'rb') as f:
        saved_wal = f.read()
    saved_xml = None
    if os.path.isfile(XML_PATH):
        with open(XML_PATH, 'rb') as f:
            saved_xml = f.read()

    rng = random.SystemRandom()
    cases = [make_case(rng, i) for i in range(2)]
    try:
        for program in (EXECUTABLE_PATH, rebuilt):
            for case_number, (quota_bytes, wal_bytes, expected) in enumerate(cases):
                with open(QUOTAS_PATH, 'wb') as f:
                    f.write(quota_bytes)
                with open(WAL_PATH, 'wb') as f:
                    f.write(wal_bytes)
                if os.path.lexists(XML_PATH):
                    os.unlink(XML_PATH)

                result = subprocess.run(
                    [program], cwd='/home/user', stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, text=True, timeout=10
                )
                assert result.returncode == 0, \
                    f'{program} failed on verification case {case_number}: {result.stderr}'
                assert os.path.isfile(XML_PATH), \
                    f'{program} did not generate {XML_PATH} on verification case {case_number}.'
                assert stat.S_ISREG(os.lstat(XML_PATH).st_mode), \
                    f'{XML_PATH} must be a regular file.'
                actual = parse_violations(XML_PATH)
                assert actual == expected, \
                    f'{program} produced {actual}, expected {expected} on verification case {case_number}.'
    finally:
        with open(QUOTAS_PATH, 'wb') as f:
            f.write(saved_quotas)
        with open(WAL_PATH, 'wb') as f:
            f.write(saved_wal)
        if os.path.lexists(XML_PATH):
            os.unlink(XML_PATH)
        if saved_xml is not None:
            with open(XML_PATH, 'wb') as f:
                f.write(saved_xml)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
