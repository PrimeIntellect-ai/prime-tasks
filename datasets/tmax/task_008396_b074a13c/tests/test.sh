#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import re
import subprocess
import textwrap

INCIDENT = '/home/user/incident'
SOURCE = os.path.join(INCIDENT, 'auth_server.cpp')
BINARY = os.path.join(INCIDENT, 'authd')
REPORT = '/home/user/incident_report.json'
SHIM_SRC = '/tmp/seccomp_audit.c'
SHIM_SO = '/tmp/seccomp_audit.so'

SHIM = r'''
#define _GNU_SOURCE
#include <seccomp.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

static void log_line(const char *kind, void *ctx, unsigned int action,
                     int syscall_num, unsigned int arg_cnt, int rc) {
    char buf[256];
    int n;
    if (kind[0] == 'I')
        n = snprintf(buf, sizeof(buf), "AUDIT INIT %p %u\n", ctx, action);
    else if (kind[0] == 'R')
        n = snprintf(buf, sizeof(buf), "AUDIT RULE %p %u %d %u\n",
                     ctx, action, syscall_num, arg_cnt);
    else
        n = snprintf(buf, sizeof(buf), "AUDIT %s %p %d\n", kind, ctx, rc);
    if (n > 0)
        syscall(SYS_write, STDERR_FILENO, buf, (size_t)n);
}

scmp_filter_ctx seccomp_init(uint32_t def_action) {
    static scmp_filter_ctx (*real_fn)(uint32_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_init");
    scmp_filter_ctx ctx = real_fn(def_action);
    log_line("INIT", ctx, def_action, 0, 0, 0);
    return ctx;
}

int seccomp_rule_add(scmp_filter_ctx ctx, uint32_t action,
                     int syscall_num, unsigned int arg_cnt, ...) {
    static int (*real_fn)(scmp_filter_ctx, uint32_t, int, unsigned int, ...);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_rule_add");
    log_line("RULE", ctx, action, syscall_num, arg_cnt, 0);
    if (arg_cnt != 0) return -1;
    return real_fn(ctx, action, syscall_num, 0);
}

int seccomp_rule_add_exact(scmp_filter_ctx ctx, uint32_t action,
                           int syscall_num, unsigned int arg_cnt, ...) {
    static int (*real_fn)(scmp_filter_ctx, uint32_t, int, unsigned int, ...);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_rule_add_exact");
    log_line("RULE", ctx, action, syscall_num, arg_cnt, 0);
    if (arg_cnt != 0) return -1;
    return real_fn(ctx, action, syscall_num, 0);
}

int seccomp_rule_add_array(scmp_filter_ctx ctx, uint32_t action,
                           int syscall_num, unsigned int arg_cnt,
                           const struct scmp_arg_cmp *arg_array) {
    static int (*real_fn)(scmp_filter_ctx, uint32_t, int, unsigned int,
                          const struct scmp_arg_cmp *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_rule_add_array");
    log_line("RULE", ctx, action, syscall_num, arg_cnt, 0);
    return real_fn(ctx, action, syscall_num, arg_cnt, arg_array);
}

int seccomp_rule_add_exact_array(scmp_filter_ctx ctx, uint32_t action,
                                 int syscall_num, unsigned int arg_cnt,
                                 const struct scmp_arg_cmp *arg_array) {
    static int (*real_fn)(scmp_filter_ctx, uint32_t, int, unsigned int,
                          const struct scmp_arg_cmp *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_rule_add_exact_array");
    log_line("RULE", ctx, action, syscall_num, arg_cnt, 0);
    return real_fn(ctx, action, syscall_num, arg_cnt, arg_array);
}

int seccomp_load(scmp_filter_ctx ctx) {
    static int (*real_fn)(scmp_filter_ctx);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_load");
    log_line("LOAD_BEFORE", ctx, 0, 0, 0, 0);
    int rc = real_fn(ctx);
    log_line("LOAD_AFTER", ctx, 0, 0, 0, rc);
    return rc;
}
'''


def build_submission_and_shim():
    assert os.path.isfile(SOURCE), f'Source file {SOURCE} does not exist.'
    assert os.path.isfile(os.path.join(INCIDENT, 'Makefile')), 'Makefile does not exist.'
    result = subprocess.run(['make', 'clean'], cwd=INCIDENT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    result = subprocess.run(['make', '-B'], cwd=INCIDENT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    assert result.returncode == 0, f'make failed:\n{result.stdout}'

    with open(SHIM_SRC, 'w') as f:
        f.write(SHIM)
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', SHIM_SRC, '-o', SHIM_SO, '-ldl'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode == 0, f'Could not build seccomp audit shim:\n{result.stdout}'


def seccomp_numbers():
    lib = ctypes.CDLL('libseccomp.so.2')
    resolve = lib.seccomp_syscall_resolve_name
    resolve.argtypes = [ctypes.c_char_p]
    resolve.restype = ctypes.c_int
    names = ['read', 'write', 'close', 'exit', 'exit_group', 'rt_sigreturn']
    values = {resolve(name.encode()) for name in names}
    assert all(value >= 0 for value in values)
    return values


def run_audited(args):
    env = os.environ.copy()
    env['LD_PRELOAD'] = SHIM_SO
    return subprocess.run([BINARY] + args, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=10)


def assert_exact_filter_and_placement(output, service_text):
    init = {}
    rules = {}
    successful = []

    for line in output.splitlines():
        m = re.fullmatch(r'AUDIT INIT (\S+) (\d+)', line)
        if m:
            init[m.group(1)] = int(m.group(2))
            continue
        m = re.fullmatch(r'AUDIT RULE (\S+) (\d+) (-?\d+) (\d+)', line)
        if m:
            rules.setdefault(m.group(1), []).append(
                (int(m.group(2)), int(m.group(3)), int(m.group(4))))
            continue
        m = re.fullmatch(r'AUDIT LOAD_AFTER (\S+) (-?\d+)', line)
        if m and int(m.group(2)) == 0:
            successful.append(m.group(1))

    allow_action = 0x7fff0000
    expected = seccomp_numbers()
    valid_contexts = []
    for ctx in successful:
        ctx_rules = rules.get(ctx, [])
        if (ctx in init and init[ctx] != allow_action and ctx_rules and
                all(action == allow_action and argc == 0 and syscall_num in expected
                    for action, syscall_num, argc in ctx_rules) and
                {syscall_num for _, syscall_num, _ in ctx_rules} == expected):
            valid_contexts.append(ctx)

    assert valid_contexts, (
        'No successfully loaded default-deny seccomp context had exactly the required '
        'six unconditional allow rules.')
    marker_positions = []
    for ctx in valid_contexts:
        marker = f'AUDIT LOAD_AFTER {ctx} 0'
        marker_positions.append(output.find(marker))
    service_pos = output.find(service_text)
    assert service_pos >= 0, f'Missing expected service output {service_text!r}. Output:\n{output}'
    assert any(0 <= pos < service_pos for pos in marker_positions), (
        'The required seccomp filter was not loaded before token processing/output.')


def test_incident_report_json():
    assert os.path.isfile(REPORT), f'Report file {REPORT} does not exist.'
    with open(REPORT) as f:
        report_data = json.load(f)

    assert 'vulnerabilities' in report_data, "Report missing 'vulnerabilities' key."
    assert 'sandboxing_library_used' in report_data, "Report missing 'sandboxing_library_used' key."
    vulns = report_data['vulnerabilities']
    assert isinstance(vulns, list), "'vulnerabilities' must be a list."
    assert 'CWE-338' in vulns or 'CWE-332' in vulns, 'Report missing correct CWE for Weak PRNG.'
    assert 'CWE-120' in vulns, 'Report missing correct CWE for Classic Buffer Overflow.'
    assert report_data['sandboxing_library_used'] == 'libseccomp', 'Incorrect sandboxing library.'
    assert set(report_data) == {'vulnerabilities', 'sandboxing_library_used'}, 'Report has unexpected keys.'
    assert vulns == ['CWE-338', 'CWE-120'], 'Report must contain the two requested official CWE IDs in order.'


def test_authd_binary_exists_and_linked():
    build_submission_and_shim()
    assert os.path.isfile(BINARY), f'Compiled binary {BINARY} does not exist.'
    assert os.access(BINARY, os.X_OK), f'File {BINARY} is not executable.'
    ldd_output = subprocess.check_output(['ldd', BINARY], stderr=subprocess.STDOUT, text=True)
    assert 'libseccomp' in ldd_output, f'Binary {BINARY} is not dynamically linked against libseccomp.'
    readelf_output = subprocess.check_output(['readelf', '-s', BINARY], stderr=subprocess.STDOUT, text=True)
    assert 'seccomp_init' in readelf_output, 'Binary does not appear to call seccomp_init.'


def test_vulnerabilities_removed_from_source():
    with open(SOURCE) as f:
        content = f.read()
    assert 'strcpy' not in content, 'The buffer overflow vulnerability (strcpy) has not been completely removed.'
    assert 'srand' not in content, 'The weak PRNG vulnerability (srand) has not been completely removed.'
    assert not re.search(r'\brand\s*\(', content), 'The service still uses rand().' 
    assert re.search(r'std::random_device|/dev/urandom|\bgetrandom\s*\(', content), (
        'No requested cryptographically secure token source is present in the implementation.')


def test_service_behavior_randomness_safe_parsing_and_seccomp():
    tokens = []
    for _ in range(6):
        result = run_audited(['generate'])
        assert result.returncode == 0, f'generate failed with {result.returncode}:\n{result.stdout}'
        assert_exact_filter_and_placement(result.stdout, 'Generated Token:')
        match = re.search(r'Generated Token:\s*([^\r\n]+)', result.stdout)
        assert match and match.group(1).strip(), f'generate returned no token:\n{result.stdout}'
        tokens.append(match.group(1).strip())
    assert len(set(tokens)) == len(tokens), 'Repeated generate executions produced duplicate tokens.'

    for token in ['short-token', 'A' * 4096, ('xY9-' * 5000)]:
        result = run_audited(['validate', token])
        assert result.returncode == 0, f'validate failed for a long token ({result.returncode}):\n{result.stdout}'
        assert_exact_filter_and_placement(result.stdout, 'Validating token:')
        assert f'Validating token: {token}' in result.stdout, 'Validation did not safely preserve the supplied token.'
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short
if [ $? -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
