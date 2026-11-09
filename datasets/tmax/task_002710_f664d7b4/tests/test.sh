#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import shutil
import struct
import subprocess
from pathlib import Path

HOME = Path('/home/user')


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def parse_records(data):
    records = []
    pos = 0
    while pos < len(data):
        assert pos + 4 <= len(data), 'Truncated record header in dump.bin'
        record_id, length = struct.unpack_from('<HH', data, pos)
        pos += 4
        assert pos + length <= len(data), 'Truncated record payload in dump.bin'
        records.append((record_id, data[pos:pos + length]))
        pos += length
    return records


def redact(payload):
    payload = re.sub(rb'(?<![0-9])[0-9]{16}(?![0-9])', b'XXXXXXXXXXXXXXXX', payload)
    return re.sub(rb'SSN: ([0-9]{3})-([0-9]{2})-([0-9]{4})',
                  b'SSN: XXX-XX-XXXX', payload)


def expected_outputs(dump):
    records = parse_records(dump)
    output = b''.join(redact(payload) for _, payload in records)
    certs = {
        f'{record_id}.pem': payload
        for record_id, payload in records
        if payload.startswith(b'-----BEGIN CERTIFICATE-----')
    }
    return records, output, certs


def valid_certificate_ids(certs):
    valid = []
    for name in sorted(certs, key=lambda n: int(Path(n).stem)):
        result = subprocess.run(
            ['openssl', 'verify', '-CAfile', str(HOME / 'rootCA.pem'),
             str(HOME / 'certs' / name)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode == 0:
            valid.append(int(Path(name).stem))
    return valid


def clean_generated_outputs():
    cert_dir = HOME / 'certs'
    if cert_dir.exists():
        shutil.rmtree(cert_dir)
    cert_dir.mkdir()
    for name in ('redacted_traffic.log',):
        try:
            (HOME / name).unlink()
        except FileNotFoundError:
            pass


def test_complete_solution():
    # Preserve the original existence and fixed-output assertions.
    for name in ('dump.bin', 'processor.c', 'redacted_traffic.log',
                 'cppcheck.log', 'valid_certs.log'):
        assert (HOME / name).is_file(), f'{HOME / name} does not exist'
    assert (HOME / 'certs').is_dir(), '/home/user/certs does not exist'
    assert list((HOME / 'certs').glob('*.pem')), 'No .pem files found in certs'

    submitted_redacted = (HOME / 'redacted_traffic.log').read_text(
        encoding='utf-8', errors='ignore')
    assert 'XXXXXXXXXXXXXXXX' in submitted_redacted
    assert 'SSN: XXX-XX-XXXX' in submitted_redacted
    assert not re.search(r'\b\d{16}\b', submitted_redacted)
    assert not re.search(r'SSN: \d{3}-\d{2}-\d{4}', submitted_redacted)
    assert (HOME / 'valid_certs.log').read_text().strip() == '2'

    # dump.bin must actually be the requested ELF section.
    extracted = Path('/tmp/traffic_dump.bin')
    run(['objcopy', '--dump-section', f'.traffic_dump={extracted}',
         str(HOME / 'capture.o')])
    original_dump = extracted.read_bytes()
    assert (HOME / 'dump.bin').read_bytes() == original_dump, \
        'dump.bin is not the raw .traffic_dump section'

    records, expected_redacted, expected_certs = expected_outputs(original_dump)
    assert expected_certs, 'The supplied dump unexpectedly has no certificates'

    # cppcheck.log must be the output of the required command on this source.
    cpp = subprocess.run(['cppcheck', '--enable=all', 'processor.c'],
                         cwd=HOME, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, check=False)
    assert (HOME / 'cppcheck.log').read_bytes() == cpp.stdout, \
        'cppcheck.log is not the cppcheck output for processor.c'

    # Compile the submitted C source using the command required by the task.
    run(['gcc', '-o', str(HOME / 'processor'),
         str(HOME / 'processor.c'), '-lseccomp'])

    # Execute it on the real dump and verify the full parsed output and exact certs.
    clean_generated_outputs()
    run([str(HOME / 'processor')], cwd=HOME, timeout=15)
    assert (HOME / 'redacted_traffic.log').read_bytes() == expected_redacted
    actual_names = sorted(p.name for p in (HOME / 'certs').glob('*.pem'))
    assert actual_names == sorted(expected_certs)
    for name, payload in expected_certs.items():
        assert (HOME / 'certs' / name).read_bytes() == payload
    expected_valid = valid_certificate_ids(expected_certs)
    assert expected_valid == [2], 'Unexpected validity of supplied certificates'
    logged = [int(x) for x in (HOME / 'valid_certs.log').read_text().split()]
    assert logged == sorted(expected_valid)

    # Build an interposer which records the actual libseccomp policy while still
    # forwarding every operation to libseccomp and loading the real filter.
    shim_source = r'''
#define _GNU_SOURCE
#include <seccomp.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
static int fd = -1;
__attribute__((constructor)) static void start_log(void) {
    const char *p = getenv("SECCOMP_AUDIT_LOG");
    if (p) fd = open(p, O_WRONLY|O_CREAT|O_TRUNC, 0600);
}
static void note(const char *fmt, ...) {
    if (fd < 0) return;
    va_list ap; va_start(ap, fmt); vdprintf(fd, fmt, ap); va_end(ap);
}
scmp_filter_ctx seccomp_init(uint32_t action) {
    static scmp_filter_ctx (*real_fn)(uint32_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_init");
    note("INIT %u\n", action);
    return real_fn(action);
}
static int add_array(const char *symbol, scmp_filter_ctx ctx, uint32_t action,
                     int syscall, unsigned int argc,
                     const struct scmp_arg_cmp *args) {
    int (*real_fn)(scmp_filter_ctx,uint32_t,int,unsigned int,const struct scmp_arg_cmp *);
    real_fn = dlsym(RTLD_NEXT, symbol);
    note("RULE %u %d %u\n", action, syscall, argc);
    return real_fn(ctx, action, syscall, argc, args);
}
int seccomp_rule_add_array(scmp_filter_ctx c, uint32_t a, int s,
                           unsigned int n, const struct scmp_arg_cmp *v) {
    return add_array("seccomp_rule_add_array", c, a, s, n, v);
}
int seccomp_rule_add_exact_array(scmp_filter_ctx c, uint32_t a, int s,
                                 unsigned int n, const struct scmp_arg_cmp *v) {
    return add_array("seccomp_rule_add_exact_array", c, a, s, n, v);
}
static int add_var(const char *symbol, scmp_filter_ctx c, uint32_t a, int s,
                   unsigned int n, va_list ap) {
    struct scmp_arg_cmp *v = n ? calloc(n, sizeof(*v)) : NULL;
    for (unsigned int i=0; i<n; i++) v[i] = va_arg(ap, struct scmp_arg_cmp);
    int rc = add_array(symbol, c, a, s, n, v);
    free(v); return rc;
}
int seccomp_rule_add(scmp_filter_ctx c, uint32_t a, int s, unsigned int n, ...) {
    va_list ap; va_start(ap,n); int rc=add_var("seccomp_rule_add_array",c,a,s,n,ap); va_end(ap); return rc;
}
int seccomp_rule_add_exact(scmp_filter_ctx c, uint32_t a, int s, unsigned int n, ...) {
    va_list ap; va_start(ap,n); int rc=add_var("seccomp_rule_add_exact_array",c,a,s,n,ap); va_end(ap); return rc;
}
int seccomp_load(scmp_filter_ctx c) {
    static int (*real_fn)(scmp_filter_ctx);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_load");
    int rc = real_fn(c);
    note("LOAD %d\n", rc);
    return rc;
}
'''
    Path('/tmp/seccomp_audit.c').write_text(shim_source)
    run(['gcc', '-shared', '-fPIC', '-o', '/tmp/seccomp_audit.so',
         '/tmp/seccomp_audit.c', '-ldl', '-lseccomp'])

    # Exercise parsing/redaction on unpredictable IDs and text while retaining
    # both supplied certificates so expected answers can be independently derived.
    cert_payloads = [p for _, p in records
                     if p.startswith(b'-----BEGIN CERTIFICATE-----')]
    assert len(cert_payloads) >= 2
    ids = random.sample(range(1000, 60000), 4)
    token = os.urandom(12).hex().encode()
    dynamic_records = [
        (ids[0], b'nonce=' + token + b'; card 8877665544332211; '
                 b'SSN: 987-65-4321; end'),
        (ids[1], cert_payloads[0]),
        (ids[2], b'keep 12345678901234567 and 123456789012345 intact; '
                 b'redact 1111222233334444'),
        (ids[3], cert_payloads[1]),
    ]
    dynamic_dump = b''.join(struct.pack('<HH', i, len(p)) + p
                            for i, p in dynamic_records)
    (HOME / 'dump.bin').write_bytes(dynamic_dump)
    _, dynamic_expected, dynamic_certs = expected_outputs(dynamic_dump)
    clean_generated_outputs()
    audit_log = '/tmp/seccomp_audit.log'
    env = os.environ.copy()
    env['LD_PRELOAD'] = '/tmp/seccomp_audit.so'
    env['SECCOMP_AUDIT_LOG'] = audit_log
    run([str(HOME / 'processor')], cwd=HOME, env=env, timeout=15)

    assert (HOME / 'redacted_traffic.log').read_bytes() == dynamic_expected
    names = sorted(p.name for p in (HOME / 'certs').glob('*.pem'))
    assert names == sorted(dynamic_certs)
    for name, payload in dynamic_certs.items():
        assert (HOME / 'certs' / name).read_bytes() == payload

    # Verify the loaded policy: process-kill default, only the nine named
    # unconditional ALLOW rules, and a successful seccomp_load.
    lines = Path(audit_log).read_text().splitlines()
    inits = [line for line in lines if line.startswith('INIT ')]
    loads = [line for line in lines if line.startswith('LOAD ')]
    rule_lines = [line for line in lines if line.startswith('RULE ')]
    assert inits == [f'INIT {0x80000000}'], \
        'seccomp default action must kill the process'
    assert loads == ['LOAD 0'], 'seccomp filter was not successfully loaded'

    lib = ctypes.CDLL('libseccomp.so.2')
    lib.seccomp_syscall_resolve_name.argtypes = [ctypes.c_char_p]
    lib.seccomp_syscall_resolve_name.restype = ctypes.c_int
    allowed_names = [b'read', b'write', b'close', b'fstat', b'mmap', b'munmap',
                     b'brk', b'exit', b'exit_group']
    expected_syscalls = {lib.seccomp_syscall_resolve_name(n) for n in allowed_names}
    observed = []
    for line in rule_lines:
        _, action, syscall, argc = line.split()
        assert int(action) == 0x7fff0000, 'Non-ALLOW seccomp rule found'
        assert int(argc) == 0, 'Conditional seccomp rules are not permitted'
        observed.append(int(syscall))
    assert len(observed) == len(expected_syscalls)
    assert set(observed) == expected_syscalls, \
        'seccomp policy does not allow exactly the required syscall set'
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
