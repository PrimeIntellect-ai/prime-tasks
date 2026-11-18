#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

FLOCK_REAL="$(readlink -f "$(command -v flock)")"
FLOCK_BACKUP="/tmp/verifier-flock-real.$$"
FLOCK_LOG="/tmp/verifier-flock.log"

cp -a "$FLOCK_REAL" "$FLOCK_BACKUP" || exit 0
: > "$FLOCK_LOG"
chmod 666 "$FLOCK_LOG"

restore_flock() {
    cp -a "$FLOCK_BACKUP" "$FLOCK_REAL" 2>/dev/null || true
    rm -f "$FLOCK_BACKUP"
}
trap restore_flock EXIT

cat > "$FLOCK_REAL" <<WRAPPER_EOF
#!/bin/bash
target=0
shared=0
for arg in "\$@"; do
    case "\$arg" in
        -s|--shared) shared=1 ;;
    esac
    resolved="\$(readlink -f -- "\$arg" 2>/dev/null || true)"
    if [[ "\$resolved" == "/home/user/combined.lock" ]]; then
        target=1
    fi
    if [[ "\$arg" =~ ^[0-9]+$ ]]; then
        fd_target="\$(readlink -f "/proc/\$\$/fd/\$arg" 2>/dev/null || true)"
        if [[ "\$fd_target" == "/home/user/combined.lock" ]]; then
            target=1
        fi
    fi
done
printf '%s %s\n' "\$target" "\$shared" >> "$FLOCK_LOG"
exec "$FLOCK_BACKUP" "\$@"
WRAPPER_EOF
chmod 755 "$FLOCK_REAL"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import gzip
import os
import signal
import subprocess
import time

SCRIPT = '/home/user/process_archives.sh'
COMBINED = '/home/user/combined_v2.json'
SUMMARY = '/home/user/summary.txt'
LOCK = '/home/user/combined.lock'
FLOCK_LOG = '/tmp/verifier-flock.log'


def expected_results():
    payloads = []
    processed = 0
    archive_dir = '/home/user/archives'
    for name in sorted(n for n in os.listdir(archive_dir) if n.endswith('.dat')):
        with open(os.path.join(archive_dir, name), 'rb') as f:
            data = f.read()
        if data[:8] == b'DATAv2.0':
            payloads.append(gzip.decompress(data[8:]))
            processed += 1
    combined = b''.join(payloads).decode('utf-8')
    return combined, processed, len(combined.splitlines())


def remove_outputs():
    for path in (COMBINED, SUMMARY):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def test_script_execution_and_flock_behavior():
    assert os.path.isfile(SCRIPT), f'Script {SCRIPT} does not exist.'
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        script_content = f.read()
    assert 'flock' in script_content, f"The script {SCRIPT} must use 'flock' to acquire a lock."

    syntax = subprocess.run(['/bin/bash', '-n', SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f'Invalid Bash script: {syntax.stderr}'

    # A process holding the required lock must prevent the script from appending.
    remove_outputs()
    lock_file = open(LOCK, 'a+')
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    proc = subprocess.Popen(['/bin/bash', SCRIPT], start_new_session=True)
    try:
        time.sleep(0.75)
        assert not os.path.exists(COMBINED) or os.path.getsize(COMBINED) == 0, (
            'The script appended data while another process held combined.lock.'
        )
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=2)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()

    remove_outputs()
    open(FLOCK_LOG, 'w').close()
    run = subprocess.run(['/bin/bash', SCRIPT], capture_output=True, text=True, timeout=15)
    assert run.returncode == 0, f'Script failed:\nstdout: {run.stdout}\nstderr: {run.stderr}'

    with open(FLOCK_LOG, 'r', encoding='utf-8') as f:
        calls = [line.strip() for line in f if line.strip()]
    assert calls, 'The script did not actually execute flock.'
    assert any(line == '1 0' for line in calls), (
        'flock was not used exclusively on /home/user/combined.lock.'
    )


def test_combined_v2_json_content():
    expected_content, _, _ = expected_results()
    assert os.path.isfile(COMBINED), f'File {COMBINED} does not exist.'
    with open(COMBINED, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert content == expected_content.strip(), f'Content of {COMBINED} is incorrect. Got:\n{content}'


def test_summary_txt_content():
    _, expected_files, expected_lines = expected_results()
    assert os.path.isfile(SUMMARY), f'File {SUMMARY} does not exist.'
    with open(SUMMARY, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()
    expected = [str(expected_files), str(expected_lines)]
    assert lines == expected, f'Expected exactly {expected} in {SUMMARY}, got {lines}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
