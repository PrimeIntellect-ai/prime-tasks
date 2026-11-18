#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import stat
import subprocess
from pathlib import Path

HOME = Path('/home/user')
PROJECT = HOME / 'cost_calc'
REPORT = HOME / 'cost_report.txt'
PORTAL = HOME / 'billing_portal.sh'


def test_rust_project_exists():
    """Test that the Rust project directory and Cargo.toml exist."""
    cargo_toml = PROJECT / 'Cargo.toml'
    assert PROJECT.is_dir(), f"Rust project directory {PROJECT} does not exist."
    assert cargo_toml.is_file(), f"Cargo.toml not found at {cargo_toml}. Did you create a Rust project?"


def archive_mb():
    total_bytes = 0
    archive_dir = HOME / 'data_archive'
    if archive_dir.is_dir():
        for root, _, files in os.walk(archive_dir):
            for name in files:
                total_bytes += os.path.getsize(os.path.join(root, name))
    return math.ceil(total_bytes / 1048576)


def test_cost_report_exists_and_content():
    """Test that the cost_report.txt file exists and contains the correct calculated total cost."""
    assert REPORT.is_file(), f"Cost report file {REPORT} does not exist."

    mb_size = archive_mb()
    rate = 0.035
    expected_cost = mb_size * rate
    expected_content = f"Total Cost: ${expected_cost:.2f}"
    actual_content = REPORT.read_text().strip()

    assert actual_content == expected_content, (
        f"Incorrect content in {REPORT}. Expected '{expected_content}', "
        f"but got '{actual_content}'."
    )


def expect_candidates():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {'target', 'data_archive', '.cargo', '.rustup'}]
        for name in files:
            path = Path(root) / name
            if path == PORTAL or path.stat().st_size > 1024 * 1024:
                continue
            try:
                text = path.read_text(errors='ignore')
            except OSError:
                continue
            if ('billing_portal.sh' in text and 'finops_secure' in text
                    and re.search(r'\bexpect\b', text)
                    and re.search(r'\bspawn\b', text)):
                candidates.append((path, text))
    return candidates


def run_expect_candidate(path, text):
    first_line = text.splitlines()[0] if text.splitlines() else ''
    if first_line.startswith('#!') and 'expect' in first_line:
        command = ['/usr/bin/expect', str(path)]
    elif re.search(r'(^|\s)(?:/usr/bin/)?expect(?:\s|$)', text):
        command = ['/bin/bash', str(path)]
    else:
        command = ['/usr/bin/expect', str(path)]
    return subprocess.run(
        command, cwd=str(HOME), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30, check=False
    )


def test_expect_script_really_authenticates_and_extracts_dynamic_rate():
    candidates = expect_candidates()
    assert candidates, 'No Expect script that spawns billing_portal.sh was found.'

    original = PORTAL.read_bytes()
    original_mode = stat.S_IMODE(PORTAL.stat().st_mode)
    marker = Path(f'/tmp/expect_authenticated_{os.getpid()}')
    challenge_rate = f"0.{random.SystemRandom().randint(101, 899)}"
    challenge = f'''#!/bin/bash
if ! [ -t 0 ]; then
    echo "Error: Interactive TTY session required."
    exit 1
fi
read -s -p "Password: " pw < /dev/tty
echo ""
if [ "$pw" = "finops_secure" ]; then
    : > "{marker}"
    echo "Authentication successful."
    echo "STORAGE_RATE_PER_MB={challenge_rate}"
else
    echo "Authentication failed."
    exit 1
fi
'''

    successes = []
    try:
        PORTAL.write_text(challenge)
        PORTAL.chmod(0o755)
        for path, text in candidates:
            marker.unlink(missing_ok=True)
            try:
                result = run_expect_candidate(path, text)
            except (subprocess.TimeoutExpired, OSError):
                continue
            if (result.returncode == 0 and marker.exists()
                    and f'STORAGE_RATE_PER_MB={challenge_rate}' in result.stdout):
                successes.append((path, text))
                break
    finally:
        PORTAL.write_bytes(original)
        PORTAL.chmod(original_mode)
        marker.unlink(missing_ok=True)

    assert successes, (
        'No submitted Expect script successfully supplied the password through a TTY '
        'and returned a dynamically changed storage rate.'
    )
    return successes[0]


def test_rust_sources_read_required_environment_variables():
    sources = []
    for path in PROJECT.rglob('*.rs'):
        if 'target' not in path.parts:
            sources.append(path.read_text(errors='ignore'))
    assert sources, 'No Rust source files were found in the project.'
    combined = '\n'.join(sources)
    assert 'STORAGE_RATE_PER_MB' in combined, 'Rust source does not reference STORAGE_RATE_PER_MB.'
    assert 'ARCHIVE_MB' in combined, 'Rust source does not reference ARCHIVE_MB.'
    assert re.search(r'(?:std::)?env::var(?:_os)?\s*\(', combined), (
        'Rust source does not read environment variables with std::env.'
    )


def build_rust_binary():
    result = subprocess.run(
        ['cargo', 'build', '--manifest-path', str(PROJECT / 'Cargo.toml'),
         '--message-format=json'],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=180, check=False
    )
    assert result.returncode == 0, f'Cargo build failed:\n{result.stderr}\n{result.stdout}'

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get('reason') == 'compiler-artifact':
            target = message.get('target', {})
            if 'bin' in target.get('kind', []) and message.get('executable'):
                executables.append(Path(message['executable']))
    assert executables, 'Cargo did not produce a Rust binary target.'
    binary = executables[-1]
    assert binary.is_file() and os.access(binary, os.X_OK), 'Compiled Rust binary is missing or not executable.'
    with binary.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'Cargo binary is not an ELF executable.'
    return binary


def test_compiled_rust_program_generates_report_from_dynamic_environment(binary):
    rng = random.SystemRandom()
    for _ in range(2):
        mb = rng.randint(17, 997)
        rate = rng.randint(11, 899) / 10000.0
        rate_text = f'{rate:.4f}'
        expected = f'Total Cost: ${mb * float(rate_text):.2f}'
        REPORT.unlink(missing_ok=True)
        env = os.environ.copy()
        env['ARCHIVE_MB'] = str(mb)
        env['STORAGE_RATE_PER_MB'] = rate_text
        result = subprocess.run(
            [str(binary)], cwd=str(PROJECT), env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30, check=False
        )
        assert result.returncode == 0, f'Compiled Rust program failed: {result.stderr}'
        assert REPORT.is_file(), 'Compiled Rust program did not create /home/user/cost_report.txt.'
        assert REPORT.read_text().strip() == expected, (
            'Compiled Rust program did not calculate the report from the supplied environment variables.'
        )


def main():
    # Preserve the original final-state assertions before exercising artifacts.
    test_rust_project_exists()
    test_cost_report_exists_and_content()
    test_expect_script_really_authenticates_and_extracts_dynamic_rate()
    test_rust_sources_read_required_environment_variables()
    binary = build_rust_binary()
    test_compiled_rust_program_generates_report_from_dynamic_environment(binary)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
