#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import time
from pathlib import Path

HOME = Path('/home/user')
MANIFESTS = HOME / 'manifests'
ACTIVE = HOME / 'active_mounts'
FSTAB = HOME / 'fstab.mock'
OPERATOR = HOME / 'operator'
SOURCE = HOME / 'operator.go'
SCRIPT = HOME / 'run_operator.sh'
VIDEO = Path('/app/operator_demo.mp4')
COUNT = 10000


def make_manifests(token):
    MANIFESTS.mkdir(parents=True, exist_ok=True)
    for entry in MANIFESTS.iterdir():
        if entry.is_dir() and not entry.is_symlink():
            subprocess.run(['/bin/rm', '-rf', str(entry)], check=True)
        else:
            entry.unlink()

    expected = []
    for i in range(1, COUNT + 1):
        namespace = f'n-{token}-{i % 23}'
        volume = f'v-{token}-{i}'
        path = MANIFESTS / f'input-{i}.yaml'
        path.write_text(
            'apiVersion: v1\n'
            'kind: PersistentVolume\n'
            'metadata:\n'
            f'  name: {volume}\n'
            f'  namespace: {namespace}\n'
        )
        expected.append((namespace, volume))
    return expected


def clean_outputs(target):
    subprocess.run(['/bin/rm', '-rf', str(target), str(ACTIVE)], check=True)
    subprocess.run(['/bin/rm', '-f', str(FSTAB)], check=True)
    ACTIVE.mkdir(parents=True, exist_ok=True)


def verify_outputs(target, backing_size, expected):
    assert target.is_dir(), f'Target directory {target} was not created'

    expected_images = set()
    expected_links = set()
    expected_fstab = set()

    for namespace, volume in expected:
        image = target / namespace / f'{volume}.img'
        expected_images.add(str(image))
        expected_links.add(volume)
        expected_fstab.add(
            f'{image} /mnt/simulated/{namespace}/{volume} ext4 loop,defaults 0 0'
        )

        assert image.is_file(), f'Backing file missing: {image}'
        data = image.read_bytes()
        assert len(data) == backing_size, (
            f'File {image} size is {len(data)}, expected exactly {backing_size} bytes'
        )
        assert data == b'\0' * backing_size, f'Backing file is not null-filled: {image}'

        link = ACTIVE / volume
        assert link.is_symlink(), f'{link} is not a symlink'
        link_target = os.readlink(link)
        assert not os.path.isabs(link_target), (
            f'Symlink target {link_target} is absolute, expected relative'
        )
        resolved = os.path.abspath(os.path.join(str(ACTIVE), link_target))
        assert resolved == str(image), f'Symlink {link} resolves to {resolved}, expected {image}'

    actual_images = {
        str(Path(root) / filename)
        for root, _, files in os.walk(target)
        for filename in files
    }
    assert actual_images == expected_images, 'Target directory contains missing or unexpected files'

    actual_links = {entry.name for entry in os.scandir(ACTIVE)}
    assert actual_links == expected_links, (
        f'Expected exactly {COUNT} correctly named active-mount entries, found {len(actual_links)}'
    )

    assert FSTAB.is_file(), f'fstab.mock file not found at {FSTAB}'
    lines = FSTAB.read_text().splitlines()
    assert len(lines) == COUNT, f'Expected {COUNT} lines in fstab.mock, found {len(lines)}'
    for line in lines:
        parts = line.split()
        assert len(parts) == 6, f'Malformed fstab entry: {line}'
        assert parts[2] == 'ext4', f'Incorrect filesystem type in fstab: {parts[2]}'
        assert parts[3] == 'loop,defaults', f'Incorrect mount options in fstab: {parts[3]}'
        assert parts[4:] == ['0', '0'], f'Incorrect trailing fstab fields: {line}'
    assert set(lines) == expected_fstab, 'fstab.mock has missing, duplicate, or incorrect entries'


def replace_and_decode_video(token):
    configured_target = f'/tmp/operator-{token}'
    configured_size = 701 + secrets.randbelow(1300)
    payload = f'TARGET_DIR={configured_target};BACKING_SIZE={configured_size}'
    qr = Path(f'/tmp/operator-{token}.png')
    frame = Path(f'/tmp/operator-{token}-frame.png')

    subprocess.run(
        ['qrencode', '-s', '8', '-m', '4', '-o', str(qr), payload],
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(
        [
            'ffmpeg', '-y', '-loglevel', 'error', '-loop', '1', '-i', str(qr),
            '-t', '2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
            '-vf', 'scale=512:512:flags=neighbor', str(VIDEO),
        ],
        check=True,
        capture_output=True,
        text=True,
    )

    subprocess.run(
        ['ffmpeg', '-y', '-loglevel', 'error', '-i', str(VIDEO), '-frames:v', '1', str(frame)],
        check=True,
        capture_output=True,
        text=True,
    )
    decoded = subprocess.run(
        ['zbarimg', '--quiet', '--raw', str(frame)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    assert decoded == payload, f'Verifier-generated QR video decoded unexpectedly: {decoded!r}'

    fields = dict(field.split('=', 1) for field in decoded.split(';'))
    return Path(fields['TARGET_DIR']), int(fields['BACKING_SIZE'])


def test_complete_operator_integration():
    # Preserve the original artifact and wrapper assertions.
    assert OPERATOR.exists(), f'Compiled operator binary not found at {OPERATOR}'
    assert os.access(OPERATOR, os.X_OK), f'Operator binary at {OPERATOR} is not executable'
    assert SOURCE.is_file(), f'Go source not found at {SOURCE}'
    assert SCRIPT.is_file(), f'Wrapper script not found at {SCRIPT}'

    content = SCRIPT.read_text()
    assert 'set -e' in content or 'set -Eeuo pipefail' in content, (
        'Script does not contain fail-fast error handling (e.g., set -e)'
    )
    assert 'PATH=' in content, 'Script does not explicitly set or export PATH'
    assert 'TARGET_DIR=' in content, 'Script does not set TARGET_DIR'
    assert 'BACKING_SIZE=' in content, 'Script does not set BACKING_SIZE'

    # Ensure the executable being exercised is built from the submitted source.
    subprocess.run(
        ['go', 'build', '-o', str(OPERATOR), str(SOURCE)],
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert os.access(OPERATOR, os.X_OK)

    token = secrets.token_hex(4)
    expected = make_manifests(token)

    # Exercise manifest parsing and both environment variables on an unpredictable
    # configuration while retaining the original 1.5-second operator metric.
    direct_target = Path(f'/tmp/direct-{secrets.token_hex(5)}')
    direct_size = 257 + secrets.randbelow(1700)
    clean_outputs(direct_target)
    env = os.environ.copy()
    env['TARGET_DIR'] = str(direct_target)
    env['BACKING_SIZE'] = str(direct_size)

    start = time.perf_counter()
    proc = subprocess.run(
        [str(OPERATOR)], env=env, cwd='/', capture_output=True, text=True, timeout=20
    )
    duration = time.perf_counter() - start
    assert proc.returncode == 0, (
        f'Operator execution failed with return code {proc.returncode}. Stderr: {proc.stderr}'
    )
    assert duration <= 1.5, (
        f'Metric failed: runtime {duration:.2f}s > 1.5s threshold. '
        'Concurrency not properly implemented.'
    )
    verify_outputs(direct_target, direct_size, expected)

    # Replace the QR video with another valid, unpredictable configuration, then
    # run the actual wrapper from / with cron's restricted PATH.
    video_target, video_size = replace_and_decode_video(secrets.token_hex(4))
    clean_outputs(video_target)
    restricted_env = {
        'PATH': '/bin',
        'HOME': '/home/user',
        'USER': 'user',
        'LOGNAME': 'user',
    }
    wrapped = subprocess.run(
        ['/bin/bash', str(SCRIPT)],
        env=restricted_env,
        cwd='/',
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert wrapped.returncode == 0, (
        f'Wrapper failed under PATH=/bin with return code {wrapped.returncode}. '
        f'Stdout: {wrapped.stdout}\nStderr: {wrapped.stderr}'
    )
    verify_outputs(video_target, video_size, expected)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
