#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import uuid

BUILD = '/home/user/build'
X86 = os.path.join(BUILD, 'auth_x86')
ARM = os.path.join(BUILD, 'auth_arm')
SCRIPT = os.path.join(BUILD, 'ci_check.py')
SOURCE = os.path.join(BUILD, 'auth_helper.c')
ALLOWLIST = os.path.join(BUILD, 'expected_symbols.txt')
LOG = os.path.join(BUILD, 'security_violations.log')


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, timeout=30, **kwargs)


def text_symbols(path):
    output = subprocess.check_output(['nm', path], text=True, timeout=30)
    names = []
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[-2] == 'T' and fields[-1].startswith('websec_'):
            names.append(fields[-1])
    return sorted(names)


def nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_makefile_and_ci_script_workflow():
    assert os.path.isfile(os.path.join(BUILD, 'Makefile')), 'Makefile is missing.'
    assert os.path.isfile(SOURCE), 'auth_helper.c is missing.'
    assert os.path.isfile(SCRIPT), 'ci_check.py is missing.'
    assert os.path.isfile(ALLOWLIST), 'expected_symbols.txt is missing.'

    # Prove that `make all` builds both outputs from the current auth_helper.c,
    # rather than accepting unrelated pre-created architecture binaries.
    with open(SOURCE, 'r') as f:
        original_source = f.read()
    marker = 'websec_verifier_' + uuid.uuid4().hex
    try:
        with open(SOURCE, 'w') as f:
            f.write(original_source)
            f.write('\nvoid %s(void) {}\n' % marker)
        for path in (X86, ARM):
            if os.path.lexists(path):
                os.remove(path)
        run(['make', 'all'], cwd=BUILD, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert marker in text_symbols(X86), 'make all did not compile the current source into auth_x86.'
        assert marker in text_symbols(ARM), 'make all did not compile the current source into auth_arm.'
    finally:
        with open(SOURCE, 'w') as f:
            f.write(original_source)

    # Rebuild the requested final binaries from the unmodified source.
    for path in (X86, ARM):
        if os.path.lexists(path):
            os.remove(path)
    run(['make', 'all'], cwd=BUILD, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    # Exercise ci_check.py on a randomized ELF so hardcoded report contents do
    # not pass. The fixture includes allowed, unauthorized, non-websec, local
    # text, and non-text symbols.
    token = uuid.uuid4().hex
    allowed = 'websec_allowed_' + token
    unauthorized = sorted([
        'websec_zeta_' + token,
        'websec_alpha_' + token,
    ])
    local_symbol = 'websec_local_' + token
    data_symbol = 'websec_data_' + token
    fixture_c = '/tmp/ci_fixture.c'
    fixture_bin = '/tmp/ci_fixture'
    with open(fixture_c, 'w') as f:
        f.write('''
void %s(void) {}
void %s(void) {}
void %s(void) {}
static void %s(void) {}
int %s = 1;
void ordinary_global(void) {}
int main(void) { %s(); %s(); %s(); %s(); return %s; }
''' % (unauthorized[1], allowed, unauthorized[0], local_symbol, data_symbol,
       unauthorized[1], allowed, unauthorized[0], local_symbol, data_symbol))
    run(['gcc', '-O0', '-o', fixture_bin, fixture_c], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    with open(ALLOWLIST, 'r') as f:
        original_allowlist = f.read()

    sentinel = 'sentinel_' + token
    nm_path = shutil.which('nm')
    assert nm_path, 'The standard nm command is unavailable.'
    real_nm = nm_path + '.verifier-real'
    nm_calls = '/tmp/nm_calls_' + token
    mode = None

    try:
        with open(ALLOWLIST, 'w') as f:
            f.write(allowed + '\n')
        with open(LOG, 'w') as f:
            f.write(sentinel + '\n')

        # Temporarily proxy the standard nm command to verify that the submitted
        # script actually invokes it with the supplied binary path.
        os.rename(nm_path, real_nm)
        try:
            with open(nm_path, 'w') as f:
                f.write('#!/bin/sh\nprintf "%s\\n" "$@" >> ' + nm_calls + '\nexec ' + real_nm + ' "$@"\n')
            os.chmod(nm_path, 0o755)
            proc = subprocess.run(
                ['python3', SCRIPT, fixture_bin],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
        finally:
            if os.path.lexists(nm_path):
                os.remove(nm_path)
            os.rename(real_nm, nm_path)

        assert proc.returncode == 0, 'ci_check.py failed on a valid binary: ' + proc.stderr
        assert os.path.isfile(nm_calls), 'ci_check.py did not execute the standard nm command.'
        with open(nm_calls, 'r') as f:
            calls = [line.strip() for line in f if line.strip()]
        assert fixture_bin in calls, 'ci_check.py did not pass its binary argument to nm.'

        logged = nonempty_lines(LOG)
        printed = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        if logged == [sentinel] + unauthorized:
            mode = 'script_logs'
        elif logged == [sentinel] and printed == unauthorized:
            mode = 'stdout'
        else:
            raise AssertionError(
                'ci_check.py did not produce the sorted unauthorized global T symbols. '
                'Log=%r stdout=%r expected=%r' % (logged, printed, unauthorized)
            )
    finally:
        if os.path.lexists(real_nm):
            if os.path.lexists(nm_path):
                os.remove(nm_path)
            os.rename(real_nm, nm_path)
        with open(ALLOWLIST, 'w') as f:
            f.write(original_allowlist)
        if os.path.exists(nm_calls):
            os.remove(nm_calls)

    # Generate the final report by actually running the submitted checker on
    # both submitted binaries. Support either a checker that appends itself or
    # one intended to be invoked with shell-style stdout append redirection.
    with open(LOG, 'w'):
        pass
    for binary in (X86, ARM):
        if mode == 'script_logs':
            proc = subprocess.run(
                ['python3', SCRIPT, binary],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
        else:
            with open(LOG, 'a') as out:
                proc = subprocess.run(
                    ['python3', SCRIPT, binary],
                    stdout=out,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
        assert proc.returncode == 0, 'ci_check.py failed for %s: %s' % (binary, proc.stderr)

    with open(ALLOWLIST, 'r') as f:
        allowed_symbols = {line.strip() for line in f if line.strip()}
    expected = []
    for binary in (X86, ARM):
        expected.extend(name for name in text_symbols(binary) if name not in allowed_symbols)
    assert nonempty_lines(LOG) == expected, 'Final report does not match an independent nm/allowlist diff.'


def test_binaries_exist():
    assert os.path.isfile('/home/user/build/auth_x86'), "auth_x86 binary is missing. Did the Makefile compile it?"
    assert os.path.isfile('/home/user/build/auth_arm'), "auth_arm binary is missing. Did the Makefile compile it?"


def test_binaries_architecture():
    # Check x86 binary
    try:
        out_x86 = subprocess.check_output(['file', '/home/user/build/auth_x86']).decode('utf-8')
        assert 'x86-64' in out_x86 or '80386' in out_x86 or 'ELF 64-bit LSB' in out_x86, "auth_x86 does not appear to be an x86 ELF binary."
    except FileNotFoundError:
        # Fallback if 'file' command is not available, we can use readelf
        out_x86 = subprocess.check_output(['readelf', '-h', '/home/user/build/auth_x86']).decode('utf-8')
        assert 'X86-64' in out_x86 or '80386' in out_x86, "auth_x86 does not appear to be an x86 ELF binary."

    # Check ARM binary
    try:
        out_arm = subprocess.check_output(['file', '/home/user/build/auth_arm']).decode('utf-8')
        assert 'aarch64' in out_arm or 'ARM' in out_arm, "auth_arm does not appear to be an ARM ELF binary."
    except FileNotFoundError:
        out_arm = subprocess.check_output(['readelf', '-h', '/home/user/build/auth_arm']).decode('utf-8')
        assert 'AArch64' in out_arm or 'ARM' in out_arm, "auth_arm does not appear to be an ARM ELF binary."


def test_security_violations_log():
    log_path = '/home/user/build/security_violations.log'
    assert os.path.isfile(log_path), f"The file {log_path} is missing."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {log_path}, found {len(lines)}."
    assert lines[0] == 'websec_debug_bypass', f"Expected 'websec_debug_bypass' on line 1, found '{lines[0]}'."
    assert lines[1] == 'websec_debug_bypass', f"Expected 'websec_debug_bypass' on line 2, found '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
