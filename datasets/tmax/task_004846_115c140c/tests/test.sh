#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile

QUOTA = 512 * 1024 * 1024


def run_monitor(script_path):
    return subprocess.run([script_path], capture_output=True, text=True)


def reset_data_dir():
    data_dir = '/home/user/data'
    if os.path.lexists(data_dir):
        if os.path.isdir(data_dir) and not os.path.islink(data_dir):
            shutil.rmtree(data_dir)
        else:
            os.unlink(data_dir)
    os.makedirs(data_dir)
    return data_dir


def assert_monitor_result(script_path, expected_code, expected_output):
    result = run_monitor(script_path)
    assert result.returncode == expected_code, (
        f"Expected exit code {expected_code}, got {result.returncode}"
    )
    assert result.stdout.strip() == expected_output, (
        f"Expected output '{expected_output}', got '{result.stdout.strip()}'"
    )
    assert result.stdout == expected_output + '\n', (
        f"Output must be exactly {expected_output!r} followed by a newline; got {result.stdout!r}"
    )


def test_disk_monitor_script():
    script_path = '/home/user/disk_monitor.py'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    data_dir = reset_data_dir()
    test_file = os.path.join(data_dir, 'test_file')

    # Preserve the original under-quota assertion.
    with open(test_file, 'wb') as f:
        f.truncate(500 * 1024 * 1024)
    assert_monitor_result(script_path, 0, 'OK')

    # Preserve the original over-quota assertion.
    with open(test_file, 'wb') as f:
        f.truncate(513 * 1024 * 1024)
    assert_monitor_result(script_path, 1, 'QUOTA_EXCEEDED')

    # Exercise the strict boundary and totals spread across unpredictable paths.
    reset_data_dir()
    nested = os.path.join(data_dir, secrets.token_hex(6), secrets.token_hex(6))
    os.makedirs(nested)
    first_size = random.SystemRandom().randint(32 * 1024 * 1024, 480 * 1024 * 1024)
    second_size = QUOTA - first_size
    with open(os.path.join(data_dir, secrets.token_hex(8)), 'wb') as f:
        f.truncate(first_size)
    second_path = os.path.join(nested, secrets.token_hex(8))
    with open(second_path, 'wb') as f:
        f.truncate(second_size)
    assert_monitor_result(script_path, 0, 'OK')

    # One byte over the quota must fail, even when the total is split among files.
    with open(second_path, 'ab') as f:
        f.truncate(second_size + 1)
    assert_monitor_result(script_path, 1, 'QUOTA_EXCEEDED')

    # Also check an unrelated dynamically selected value safely below the quota.
    reset_data_dir()
    under = random.SystemRandom().randint(1, QUOTA - 2)
    with open(os.path.join(data_dir, secrets.token_hex(8)), 'wb') as f:
        f.truncate(under)
    assert_monitor_result(script_path, 0, 'OK')

    reset_data_dir()


def parse_unit(path):
    sections = {}
    current = None
    with open(path, 'r', encoding='utf-8') as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith('#') or line.startswith(';'):
                continue
            if line.startswith('[') and line.endswith(']'):
                current = line[1:-1]
                assert current, f"Empty section name on line {lineno}"
                sections.setdefault(current, {})
                continue
            assert current is not None, f"Directive outside a section on line {lineno}"
            assert '=' in line, f"Invalid unit directive on line {lineno}: {line!r}"
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip()
            assert key, f"Empty directive name on line {lineno}"
            sections[current].setdefault(key, []).append(value)
    return sections


def test_systemd_service():
    service_path = '/home/user/.config/systemd/user/disk-monitor.service'
    assert os.path.isfile(service_path), f"Service file {service_path} does not exist."

    with open(service_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Preserve the original assertions.
    assert "ExecStart=/home/user/disk_monitor.py" in content, "Service file missing correct ExecStart directive."
    assert "Restart=on-failure" in content, "Service file missing correct Restart directive."

    sections = parse_unit(service_path)
    assert 'Service' in sections, "Service file is missing a [Service] section."
    service = sections['Service']
    assert service.get('ExecStart') == ['/home/user/disk_monitor.py'], (
        "[Service] must contain exactly ExecStart=/home/user/disk_monitor.py"
    )
    assert service.get('Restart') == ['on-failure'], (
        "[Service] must contain exactly Restart=on-failure"
    )

    analyzer = shutil.which('systemd-analyze')
    assert analyzer is not None, "systemd-analyze is unavailable for unit validation."
    result = subprocess.run(
        [analyzer, 'verify', service_path], capture_output=True, text=True
    )
    assert result.returncode == 0, (
        "systemd unit validation failed:\n" + result.stdout + result.stderr
    )


def test_ssh_filter_corpus():
    script_path = '/home/user/ssh_filter.py'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    evil_failed = []

    for cf in clean_files:
        res = subprocess.run(['python3', script_path, cf], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        res = subprocess.run(['python3', script_path, ef], capture_output=True)
        if res.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")

    assert not error_msgs, " | ".join(error_msgs)


def varied_case(text, rng):
    return ''.join(rng.choice((c.lower(), c.upper())) if c.isalpha() else c for c in text)


def test_ssh_filter_dynamic_configs():
    script_path = '/home/user/ssh_filter.py'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix='ssh-input-') as tmp:
        cases = []

        clean_text = (
            "# PubkeyAuthentication no\n"
            "Host " + secrets.token_hex(5) + "\n"
            "\t" + varied_case('PubkeyAuthentication', rng) + "   yes\n"
            "  " + varied_case('AuthorizedKeysFile', rng) + "\t.ssh/authorized_keys\n"
        )
        cases.append((clean_text, 0))

        clean_text_2 = (
            "Host *\n"
            "  Port 22\n"
            "  # AuthorizedKeysFile /dev/null\n"
            "  User " + secrets.token_hex(4) + "\n"
        )
        cases.append((clean_text_2, 0))

        evil_pubkey = (
            "Host " + secrets.token_hex(5) + "\n" +
            (" " * rng.randint(1, 7)) + varied_case('PubkeyAuthentication', rng) +
            ("\t" * rng.randint(1, 3)) + varied_case('no', rng) + "\n"
        )
        cases.append((evil_pubkey, 1))

        evil_keys = (
            "Host *\n" +
            ("\t" * rng.randint(1, 3)) + varied_case('AuthorizedKeysFile', rng) +
            (" " * rng.randint(2, 8)) + '/dev/null' + "\n"
        )
        cases.append((evil_keys, 1))

        evil_mixed = (
            "Host *\n"
            "  PubkeyAuthentication yes\n"
            "Match User " + secrets.token_hex(4) + "\n"
            "  " + varied_case('AuthorizedKeysFile', rng) + "\t/dev/null\n"
        )
        cases.append((evil_mixed, 1))

        rng.shuffle(cases)
        for index, (content, expected) in enumerate(cases):
            path = os.path.join(tmp, secrets.token_hex(10) + f'-{index}.conf')
            with open(path, 'w', encoding='utf-8') as f:
                f.write(content)
            result = subprocess.run(
                ['python3', script_path, path], capture_output=True, text=True
            )
            assert result.returncode == expected, (
                f"Dynamic SSH config was classified incorrectly; expected exit "
                f"{expected}, got {result.returncode}. Config was:\n{content}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
