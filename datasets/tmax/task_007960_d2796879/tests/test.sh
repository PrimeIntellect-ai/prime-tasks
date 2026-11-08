#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid


def normalize(data):
    seen = set()
    output = []
    for line in data.splitlines():
        line = line.split('#', 1)[0].strip()
        if line and line not in seen:
            seen.add(line)
            output.append(line)
    return ''.join(line + '\n' for line in output)


def run_cleaner(path, data):
    result = subprocess.run(
        [path], input=data, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def test_cleaner_executable():
    """Check if /home/user/cleaner exists and is executable."""
    path = '/home/user/cleaner'
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{path} is not a compiled executable."


def test_process_sh_executable():
    """Check if /home/user/process.sh exists and is executable."""
    path = '/home/user/process.sh'
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_cleaner_source_compiles_and_handles_novel_input():
    source = '/home/user/cleaner.cpp'
    assert os.path.isfile(source), f"Source file {source} does not exist."

    data = (
        "   alpha = one   # first comment\n"
        "\tbeta=two\t# second comment\n"
        "alpha = one\n"
        "  alpha = one   \n"
        "# comment-only line\n"
        "     \n"
        " value = three#attached comment\n"
        "value = three\n"
        "gamma = spaced value   \n"
    )
    expected = normalize(data)
    assert run_cleaner('/home/user/cleaner', data) == expected

    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, 'cleaner')
        result = subprocess.run(
            ['g++', '-std=c++17', source, '-o', rebuilt],
            text=True, capture_output=True, timeout=30
        )
        assert result.returncode == 0, result.stderr
        assert run_cleaner(rebuilt, data) == expected


def test_process_pipeline_on_novel_file():
    token = uuid.uuid4().hex
    basename = f'audit novel {token}.conf'
    raw_path = os.path.join('/home/user/raw_configs', basename)
    clean_path = os.path.join('/home/user/clean_configs', basename)
    data = (
        " # generated test input\n"
        "  endpoint = example.internal   # remove this\n"
        "timeout=91\n"
        "endpoint = example.internal\n"
        "\tmode = active\t\n"
        "timeout=91 # duplicate after normalization\n"
    )
    expected = normalize(data)

    with open(raw_path, 'w') as f:
        f.write(data)
    if os.path.exists(clean_path):
        os.unlink(clean_path)

    try:
        result = subprocess.run(
            ['/home/user/process.sh'], text=True, capture_output=True, timeout=20
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(clean_path), 'Pipeline did not create the matching output file.'
        with open(clean_path) as f:
            assert f.read() == expected
    finally:
        for path in (raw_path, clean_path):
            if os.path.exists(path):
                os.unlink(path)


def test_process_pipeline_invokes_cleaner():
    token = uuid.uuid4().hex
    basename = f'cleaner_probe_{token}.conf'
    raw_path = os.path.join('/home/user/raw_configs', basename)
    clean_path = os.path.join('/home/user/clean_configs', basename)
    cleaner = '/home/user/cleaner'
    backup = f'/tmp/cleaner_backup_{token}'

    with open(raw_path, 'w') as f:
        f.write('input-that-the-probe-must-receive\n')

    os.replace(cleaner, backup)
    try:
        with open(cleaner, 'w') as f:
            f.write('#!/bin/sh\ncat >/dev/null\nprintf "cleaner-was-invoked\\n"\n')
        os.chmod(cleaner, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                          stat.S_IRGRP | stat.S_IXGRP |
                          stat.S_IROTH | stat.S_IXOTH)
        result = subprocess.run(
            ['/home/user/process.sh'], text=True, capture_output=True, timeout=20
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(clean_path)
        with open(clean_path) as f:
            assert f.read() == 'cleaner-was-invoked\n', \
                'process.sh did not pass the file through /home/user/cleaner.'
    finally:
        if os.path.lexists(cleaner):
            os.unlink(cleaner)
        os.replace(backup, cleaner)
        if os.path.exists(raw_path):
            os.unlink(raw_path)
        if os.path.exists(clean_path):
            os.unlink(clean_path)
        subprocess.run(['/home/user/process.sh'], timeout=20, check=True)


def test_clean_configs_server1():
    """Check contents of /home/user/clean_configs/server1.conf."""
    path = '/home/user/clean_configs/server1.conf'
    assert os.path.isfile(path), f"Cleaned config {path} does not exist."

    expected_content = "host = 192.168.1.10\nport=8080\ntimeout = 30\n"
    with open(path, 'r') as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Content of {path} is incorrect."


def test_clean_configs_server2():
    """Check contents of /home/user/clean_configs/server2.conf."""
    path = '/home/user/clean_configs/server2.conf'
    assert os.path.isfile(path), f"Cleaned config {path} does not exist."

    expected_content = "loglevel=debug\npath=/var/log/app.log\n"
    with open(path, 'r') as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), f"Content of {path} is incorrect."


def test_cron_txt():
    """Check if /home/user/cron.txt contains the correct cron job."""
    path = '/home/user/cron.txt'
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    assert len(content.splitlines()) == 1, f"{path} must contain exactly one crontab line."
    pattern = r'^(\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*\s+/home/user/process\.sh$'
    assert re.match(pattern, content), f"Content of {path} does not match the expected crontab format."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
