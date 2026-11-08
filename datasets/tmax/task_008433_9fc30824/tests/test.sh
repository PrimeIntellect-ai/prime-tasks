#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /home/user/login_simulator.sh /tmp/login_simulator.original
restore_simulator() {
    cp /tmp/login_simulator.original /home/user/login_simulator.sh
    chmod +x /home/user/login_simulator.sh
}
trap restore_simulator EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

C_PATH = '/home/user/stealth_auth.c'
EXE_PATH = '/home/user/stealth_auth'
SIMULATOR = '/home/user/login_simulator.sh'
LOG_PATH = '/home/user/auth_result.log'
REBUILT_PATH = '/tmp/stealth_auth_rebuilt'
PROBE_TOKEN = '/tmp/stealth_probe_token'
PROBE_PID = '/tmp/stealth_probe_pid'
PROBE_CMDLINE = '/tmp/stealth_probe_cmdline'
PROBE_ARGS = '/tmp/stealth_probe_args'


def test_stealth_auth_c_exists():
    assert os.path.isfile(C_PATH), f"The source file {C_PATH} does not exist."


def test_stealth_auth_executable_exists():
    assert os.path.isfile(EXE_PATH), f"The executable {EXE_PATH} does not exist."
    st = os.stat(EXE_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file {EXE_PATH} is not executable."
    with open(EXE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"The executable {EXE_PATH} is not a compiled ELF program."


def test_stealth_auth_execution():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    # The hex string for "sysadmin_secret_991" XORed with 0x7F
    hex_input = "0c060c1e1b121611200c1a1c0d1a0b2046464e\n"

    try:
        process = subprocess.run(
            [EXE_PATH],
            input=hex_input,
            text=True,
            capture_output=True,
            timeout=5
        )
    except Exception as e:
        assert False, f"Failed to execute {EXE_PATH}: {e}"

    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} was not created after running the executable."

    with open(LOG_PATH, 'r') as f:
        content = f.read().strip()

    assert content == "ACCESS_GRANTED", f"Expected 'ACCESS_GRANTED' in {LOG_PATH}, but got '{content}'."


def _install_probe_simulator():
    probe = '''#!/bin/bash
umask 077
printf '%s' "${AUTH_TOKEN-}" > /tmp/stealth_probe_token
printf '%s' "$$" > /tmp/stealth_probe_pid
cat /proc/$$/cmdline > /tmp/stealth_probe_cmdline
printf '%s\\0' "$@" > /tmp/stealth_probe_args
'''
    with open(SIMULATOR, 'w') as f:
        f.write(probe)
    os.chmod(SIMULATOR, 0o755)


def _xor_hex(token):
    return ''.join(f'{b ^ 0x7f:02x}' for b in token.encode('ascii'))


def _exercise(executable, token, include_second_line=False):
    for path in (PROBE_TOKEN, PROBE_PID, PROBE_CMDLINE, PROBE_ARGS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    input_text = _xor_hex(token) + '\n'
    if include_second_line:
        input_text += _xor_hex('must_not_be_used') + '\n'

    env = os.environ.copy()
    env.pop('AUTH_TOKEN', None)
    proc = subprocess.Popen(
        [executable],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    original_pid = proc.pid
    try:
        stdout, stderr = proc.communicate(input=input_text, timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise AssertionError(f'{executable} timed out')

    assert proc.returncode == 0, (
        f'{executable} exited with {proc.returncode}; stdout={stdout!r}, stderr={stderr!r}'
    )
    for path in (PROBE_TOKEN, PROBE_PID, PROBE_CMDLINE, PROBE_ARGS):
        assert os.path.isfile(path), f'Target script did not create probe output {path}'

    with open(PROBE_TOKEN, 'r') as f:
        observed_token = f.read()
    assert observed_token == token, (
        'AUTH_TOKEN did not contain the token obtained by hex decoding and XOR with 0x7F'
    )

    with open(PROBE_PID, 'r') as f:
        target_pid = int(f.read())
    assert target_pid == original_pid, (
        'The target script did not replace the submitted process via exec'
    )

    token_bytes = token.encode('ascii')
    with open(PROBE_CMDLINE, 'rb') as f:
        cmdline = f.read()
    with open(PROBE_ARGS, 'rb') as f:
        script_args = f.read()
    assert token_bytes not in cmdline, 'The decrypted token was exposed in the process command line'
    assert token_bytes not in script_args, 'The decrypted token was passed as a script argument'


def test_randomized_decoding_environment_and_exec_behavior():
    with open(C_PATH, 'r', errors='replace') as f:
        source = f.read()
    assert re.search(r'\b(?:execl|execle|execlp|execv|execve|execvp|execvpe)\s*\(', source), (
        'The C source does not call an exec-family function'
    )

    build = subprocess.run(
        ['gcc', C_PATH, '-o', REBUILT_PATH],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert build.returncode == 0, (
        f'gcc could not compile {C_PATH}: stdout={build.stdout!r}, stderr={build.stderr!r}'
    )

    _install_probe_simulator()

    # Answers are generated at verification time rather than taken from the shipped simulator.
    submitted_token = 'probe_' + secrets.token_hex(16)
    rebuilt_token = 'verify_' + secrets.token_hex(19)
    second_line_token = 'line_' + secrets.token_hex(11)

    _exercise(EXE_PATH, submitted_token)
    _exercise(REBUILT_PATH, rebuilt_token)
    _exercise(REBUILT_PATH, second_line_token, include_second_line=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
