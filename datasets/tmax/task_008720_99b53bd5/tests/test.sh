#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile


def strip_comments_and_literals(src):
    pattern = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)
    return pattern.sub(lambda m: '\n' * m.group(0).count('\n') if m.group(0).startswith(('/', '"', "'")) else '', src)


def function_body(src, name):
    match = re.search(r'\b' + re.escape(name) + r'\s*\([^;{}]*\)\s*\{', src)
    assert match, f"Missing definition of function {name}"
    start = match.end() - 1
    depth = 0
    for pos in range(start, len(src)):
        if src[pos] == '{':
            depth += 1
        elif src[pos] == '}':
            depth -= 1
            if depth == 0:
                return src[start + 1:pos]
    raise AssertionError(f"Unterminated definition of {name}")


def global_pointer_names(src):
    names = set()
    depth = 0
    statement = []
    for char in src:
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
        if depth == 0:
            statement.append(char)
            if char == ';':
                text = ''.join(statement)
                statement = []
                if '(' not in text:
                    for match in re.finditer(r'\*\s*([A-Za-z_]\w*)\s*(?:=|;|,|\[)', text):
                        names.add(match.group(1))
    return names


def assert_real_program_structure(path, patched):
    with open(path, 'r') as f:
        raw = f.read()
    src = strip_comments_and_literals(raw)

    health = function_body(src, 'check_health')
    report = function_body(src, 'report_status')
    main = function_body(src, 'main')

    assert re.search(r'\bmalloc\s*\(', health), "check_health must actually call malloc"
    assert re.search(r'\bfree\s*\(', report), "report_status must actually call free"

    pointers = global_pointer_names(src)
    shared = [name for name in pointers
              if re.search(r'\b' + re.escape(name) + r'\b', health)
              and re.search(r'\b' + re.escape(name) + r'\b', report)]
    assert shared, "Both thread functions must operate on the same global pointer"

    assert re.search(r'\bpthread_create\s*\([^;]*\bcheck_health\b', main), \
        "main must create a check_health thread"
    assert re.search(r'\bpthread_create\s*\([^;]*\breport_status\b', main), \
        "main must create a report_status thread"
    assert re.search(r'\b(?:for|while)\s*\(|\bdo\b', main), \
        "main must spawn the threads in a loop"

    if patched:
        for name, body, operation in [
            ('check_health', health, 'malloc'),
            ('report_status', report, 'free'),
        ]:
            lock = re.search(r'\bpthread_mutex_lock\s*\(\s*&\s*uptime_mutex\s*\)', body)
            op = re.search(r'\b' + operation + r'\s*\(', body)
            unlocks = list(re.finditer(r'\bpthread_mutex_unlock\s*\(\s*&\s*uptime_mutex\s*\)', body))
            assert lock and op and unlocks, f"{name} must lock and unlock uptime_mutex around {operation}"
            unlock = next((item for item in unlocks if item.start() > op.start()), None)
            assert lock.start() < op.start() and unlock, \
                f"{operation} in {name} is not inside an uptime_mutex critical section"
            protected = body[lock.end():unlock.start()]
            assert any(re.search(r'\b' + re.escape(ptr) + r'\b', protected) for ptr in shared), \
                f"{name}'s protected critical section must access the shared pointer"


def compile_program(source, output):
    result = subprocess.run(
        ['gcc', '-pthread', '-O0', '-g', '-rdynamic', '-o', output, source],
        capture_output=True, text=True)
    assert result.returncode == 0, f"{source} failed to compile:\n{result.stderr}"


def build_tracer():
    tracer_src = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void note(const char *text) {
    const char *path = getenv("TRACE_FILE");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) { write(fd, text, strlen(text)); close(fd); }
}

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start)(void *), void *arg) {
    static int (*real_create)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
    if (!real_create) real_create = dlsym(RTLD_NEXT, "pthread_create");
    int rc = real_create(thread, attr, start, arg);
    if (rc == 0 && start == dlsym(RTLD_DEFAULT, "check_health")) note("HC\n");
    if (rc == 0 && start == dlsym(RTLD_DEFAULT, "report_status")) note("RC\n");
    return rc;
}

int pthread_mutex_lock(pthread_mutex_t *mutex) {
    static int (*real_lock)(pthread_mutex_t *);
    if (!real_lock) real_lock = dlsym(RTLD_NEXT, "pthread_mutex_lock");
    int rc = real_lock(mutex);
    void *target = dlsym(RTLD_DEFAULT, "uptime_mutex");
    if (rc == 0 && target && mutex == (pthread_mutex_t *)target) {
        void *health = dlsym(RTLD_DEFAULT, "check_health");
        void *report = dlsym(RTLD_DEFAULT, "report_status");
        Dl_info info;
        if (dladdr(__builtin_return_address(0), &info) && info.dli_saddr == health) note("HL\n");
        if (dladdr(__builtin_return_address(0), &info) && info.dli_saddr == report) note("RL\n");
    }
    return rc;
}
'''
    src = '/tmp/trace_threads.c'
    out = '/tmp/trace_threads.so'
    with open(src, 'w') as f:
        f.write(tracer_src)
    result = subprocess.run(['gcc', '-shared', '-fPIC', '-o', out, src, '-ldl', '-pthread'],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return out


def trace_run(binary, require_locks):
    tracer = build_tracer()
    fd, trace = tempfile.mkstemp(prefix='uptime-trace-')
    os.close(fd)
    env = os.environ.copy()
    env['LD_PRELOAD'] = tracer
    env['TRACE_FILE'] = trace
    try:
        try:
            result = subprocess.run([binary], timeout=2, capture_output=True, env=env)
            if require_locks:
                assert result.returncode not in [134, 139, -6, -11], \
                    f"patched binary crashed with exit code {result.returncode}"
        except subprocess.TimeoutExpired:
            pass
        with open(trace, 'r') as f:
            events = f.read().splitlines()
    finally:
        os.unlink(trace)

    assert 'HC' in events, "The executable did not create a thread running check_health"
    assert 'RC' in events, "The executable did not create a thread running report_status"
    if require_locks:
        assert 'HL' in events, "check_health did not actually lock the global uptime_mutex"
        assert 'RL' in events, "report_status did not actually lock the global uptime_mutex"


def test_bug_report():
    path = '/home/user/bug_report.txt'
    assert os.path.exists(path), f"File {path} is missing."
    with open(path, 'r') as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]
    expected = {'check_health', 'report_status'}
    assert set(lines) == expected, f"bug_report.txt must contain exactly the two function names. Found: {lines}"
    assert len(lines) == 2, "bug_report.txt must contain exactly two non-empty lines"


def test_mre_c():
    path = '/home/user/mre.c'
    assert os.path.exists(path), f"File {path} is missing."
    with open(path, 'r') as f:
        content = f.read()
    for req in ['check_health', 'report_status', 'malloc', 'free']:
        assert req in content, f"mre.c must contain '{req}'"
    assert 'pthread_mutex_lock' not in content, "mre.c must NOT contain 'pthread_mutex_lock'"

    result = subprocess.run(['gcc', '-pthread', '-o', '/tmp/mre_bin', path], capture_output=True, text=True)
    assert result.returncode == 0, f"mre.c failed to compile:\n{result.stderr}"
    assert_real_program_structure(path, patched=False)
    compile_program(path, '/tmp/mre_trace_bin')
    trace_run('/tmp/mre_trace_bin', require_locks=False)


def test_patched_c():
    path = '/home/user/patched.c'
    assert os.path.exists(path), f"File {path} is missing."
    with open(path, 'r') as f:
        content = f.read()

    normalized = re.sub(r'\s+', ' ', content)
    no_spaces = content.replace(' ', '').replace('\t', '').replace('\n', '')
    assert 'pthread_mutex_t uptime_mutex' in normalized or 'pthread_mutex_tuptime_mutex' in no_spaces, \
        "patched.c must contain 'pthread_mutex_t uptime_mutex'"
    assert 'pthread_mutex_lock(&uptime_mutex)' in no_spaces, \
        "patched.c must contain 'pthread_mutex_lock(&uptime_mutex)'"
    assert 'pthread_mutex_unlock(&uptime_mutex)' in no_spaces, \
        "patched.c must contain 'pthread_mutex_unlock(&uptime_mutex)'"

    result = subprocess.run(['gcc', '-pthread', '-o', '/tmp/patched_bin', path], capture_output=True, text=True)
    assert result.returncode == 0, f"patched.c failed to compile:\n{result.stderr}"
    try:
        run_result = subprocess.run(['/tmp/patched_bin'], timeout=2, capture_output=True)
        assert run_result.returncode not in [134, 139], \
            f"patched binary crashed with exit code {run_result.returncode}"
    except subprocess.TimeoutExpired:
        pass

    assert_real_program_structure(path, patched=True)
    compile_program(path, '/tmp/patched_trace_bin')
    trace_run('/tmp/patched_trace_bin', require_locks=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
