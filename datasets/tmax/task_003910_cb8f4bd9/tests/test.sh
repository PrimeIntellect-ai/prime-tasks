#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tempfile
import time
import uuid

FINAL_DIR = '/home/user/artifacts/final'
BACKLOG_DIR = '/home/user/artifacts/backlog'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)


def regular_files(path):
    return [f for f in os.listdir(path) if os.path.isfile(os.path.join(path, f))]


def elf_machine(path):
    output = run(['readelf', '-h', path], text=True).stdout
    match = re.search(r'^\s*Machine:\s*(.+?)\s*$', output, re.MULTILINE)
    assert match, f'Could not determine ELF architecture for {path}'
    return match.group(1)


def allocated_sections(path):
    output = run(['readelf', '-SW', path], text=True).stdout
    sections = []
    pattern = re.compile(
        r'^\s*\[\s*\d+\]\s+(\S+)\s+(\S+)\s+'
        r'[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+\S+\s+(\S+)'
    )
    for line in output.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        name, section_type, flags = match.groups()
        if 'A' in flags and section_type != 'NOBITS' and name:
            sections.append(name)
    return sections


def section_digest(path, section):
    with tempfile.NamedTemporaryFile() as dumped:
        result = subprocess.run(
            ['objcopy', '--dump-section', f'{section}={dumped.name}', path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert result.returncode == 0, (
            f'Could not read section {section} from {path}: '
            f'{result.stderr.decode(errors="replace")}'
        )
        dumped.seek(0)
        return hashlib.sha256(dumped.read()).hexdigest()


def test_final_artifacts_count():
    """Verify that exactly 50 artifacts were successfully uploaded and moved to the final directory."""
    assert os.path.isdir(FINAL_DIR), f'Final directory {FINAL_DIR} does not exist. Did you upload the files?'
    files = regular_files(FINAL_DIR)
    assert len(files) == 50, f'Expected exactly 50 files in {FINAL_DIR}, but found {len(files)}.'


def test_final_artifacts_size_threshold():
    """Verify that the total size is below the original stripping threshold."""
    assert os.path.isdir(FINAL_DIR), f'Final directory {FINAL_DIR} does not exist.'
    total_size = sum(os.path.getsize(os.path.join(FINAL_DIR, f)) for f in regular_files(FINAL_DIR))
    threshold = 800000
    assert total_size < threshold, (
        f'Total size of artifacts is {total_size} bytes, which is >= {threshold} bytes. '
        'Did you strip the debug symbols from the binaries before uploading?'
    )


def test_final_artifacts_naming_convention():
    """Verify the original naming assertions and that every backlog filename occurs exactly once."""
    assert os.path.isdir(FINAL_DIR), f'Final directory {FINAL_DIR} does not exist.'
    files = regular_files(FINAL_DIR)
    seen = set()
    for filename in files:
        assert filename.startswith('arch_'), (
            f"File {filename} does not follow the naming convention "
            "'arch_<architecture_string>_<original_filename>'."
        )
        assert ' ' not in filename, f'File {filename} contains spaces, which should have been replaced by hyphens.'
        match = re.fullmatch(r'arch_(.+)_(binary_[1-9]|binary_[1-4][0-9]|binary_50)', filename)
        assert match, f'{filename} does not identify one of the 50 original backlog files.'
        arch, original = match.groups()
        assert original not in seen, f'{original} was represented more than once.'
        seen.add(original)

        machine = elf_machine(os.path.join(BACKLOG_DIR, original)).lower()
        normalized = arch.lower().replace('_', '-').replace(' ', '-')
        if 'x86-64' in machine or 'advanced micro devices' in machine:
            assert normalized in {'x86-64', 'amd64', 'advanced-micro-devices-x86-64'}, (
                f'Architecture {arch!r} is not correct for {original} ({machine}).'
            )
        elif 'aarch64' in machine:
            assert normalized in {'aarch64', 'arm64'}, f'Architecture {arch!r} is not correct for {original}.'
        elif 'arm' in machine:
            assert normalized.startswith('arm'), f'Architecture {arch!r} is not correct for {original}.'
        else:
            expected = re.sub(r'\s+', '-', machine.strip())
            assert normalized == expected, f'Architecture {arch!r} is not correct for {original}.'

    expected = {f'binary_{i}' for i in range(1, 51)}
    assert seen == expected, f'Missing original artifacts: {sorted(expected - seen)}'


def test_artifacts_are_corresponding_stripped_elf_files():
    """Reject fabricated files and verify that each result is its corresponding stripped ELF."""
    for filename in regular_files(FINAL_DIR):
        match = re.fullmatch(r'arch_(.+)_(binary_[1-9]|binary_[1-4][0-9]|binary_50)', filename)
        assert match, f'Unexpected final filename: {filename}'
        original = match.group(2)
        source = os.path.join(BACKLOG_DIR, original)
        result = os.path.join(FINAL_DIR, filename)

        assert os.path.isfile(source), f'Original backlog artifact {source} is missing.'
        assert os.path.getsize(result) < os.path.getsize(source), f'{filename} was not reduced in size.'
        assert elf_machine(result) == elf_machine(source), f'{filename} has the wrong ELF architecture.'

        section_output = run(['readelf', '-SW', result], text=True).stdout
        assert not re.search(r'\.(?:z?debug)(?:_|\b)', section_output), (
            f'{filename} still contains debug sections.'
        )

        source_sections = allocated_sections(source)
        result_sections = set(allocated_sections(result))
        assert source_sections, f'No allocated ELF sections found in {source}.'
        for section in source_sections:
            assert section in result_sections, f'{filename} is missing allocated section {section}.'
            assert section_digest(result, section) == section_digest(source, section), (
                f'{filename} does not contain the original data for ELF section {section}.'
            )

        executed = subprocess.run(
            [result], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3, text=True
        )
        assert executed.returncode == 0, f'{filename} is not a working executable ELF file.'
        assert executed.stdout == 'Hello World\n', f'{filename} does not behave like its source artifact.'


def test_services_configured_correctly():
    """Verify that required configuration files exist and contain the corrected ports."""
    nginx_conf = '/app/nginx.conf'
    assert os.path.isfile(nginx_conf), 'Required Nginx configuration /app/nginx.conf is missing.'
    with open(nginx_conf) as f:
        content = f.read()
    assert '127.0.0.1:5000' in content, 'Nginx config does not point to the correct Flask port (5000).'
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:5000\s*;', content), (
        'Nginx proxy_pass is not configured for the Flask service on port 5000.'
    )
    run(['nginx', '-t', '-c', nginx_conf])

    env_file = '/app/.env'
    assert os.path.isfile(env_file), 'Required Flask environment configuration /app/.env is missing.'
    with open(env_file) as f:
        content = f.read()
    assert '6379' in content, 'Flask .env does not point to the correct Redis port (6379).'
    values = {}
    for line in content.splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('"\'')
    assert values.get('REDIS_HOST') == '127.0.0.1', 'REDIS_HOST is not configured correctly.'
    assert values.get('REDIS_PORT') == '6379', 'REDIS_PORT is not configured correctly.'


def test_live_end_to_end_upload_pipeline():
    """Exercise Nginx, Flask, Redis, and the worker rather than trusting final-directory shape."""
    probe_name = f'verifier_probe_{uuid.uuid4().hex}'
    probe_path = os.path.join('/tmp', probe_name)
    destination = os.path.join(FINAL_DIR, probe_name)
    payload = os.urandom(257)
    with open(probe_path, 'wb') as f:
        f.write(payload)

    try:
        response = subprocess.run(
            ['curl', '--silent', '--show-error', '--fail', '--max-time', '5',
             '-F', f'file=@{probe_path};filename={probe_name}',
             'http://127.0.0.1:8080/upload'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert response.returncode == 0, (
            'Upload through Nginx failed: ' + response.stderr.decode(errors='replace')
        )
        deadline = time.time() + 15
        while time.time() < deadline and not os.path.isfile(destination):
            time.sleep(0.2)
        assert os.path.isfile(destination), 'The Redis worker did not move the uploaded probe into final/.'
        with open(destination, 'rb') as f:
            assert f.read() == payload, 'The end-to-end pipeline corrupted the uploaded content.'
    finally:
        for path in (probe_path, destination):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
