#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/archive_instrument
mkdir -p /tmp/archive_instrument
cat <<'PYEOF' > /tmp/archive_instrument/sitecustomize.py
import os
try:
    import fcntl
    _real_flock = fcntl.flock
    def _logged_flock(fd, operation):
        try:
            line = "FLOCK %d %d\n" % (os.getpid(), int(operation))
            logfd = os.open('/tmp/archive_flock.log', os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
            try:
                os.write(logfd, line.encode('ascii'))
            finally:
                os.close(logfd)
        except Exception:
            pass
        return _real_flock(fd, operation)
    fcntl.flock = _logged_flock
except Exception:
    pass
PYEOF

cat <<'PYEOF' > /tmp/test_final_state.py
import ast
import os
import re
import shutil
import struct
import subprocess
import zlib

import cv2
from skimage.metrics import structural_similarity as ssim

ARCHIVE = '/home/user/video_archive.bin'
RESTORED = '/home/user/restored_frames'
VIDEO = '/app/surveillance.mp4'


def find_script(name):
    for path in ('/home/user/' + name, '/app/' + name):
        if os.path.isfile(path):
            return path
    raise AssertionError(name + ' script not found')


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def natural_key(name):
    return [int(x) if x.isdigit() else x.lower() for x in re.split(r'(\d+)', name)]


def reference_frames():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), 'Could not open original video'
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not fps or fps != fps:
        fps = 30.0
    interval = max(1, int(round(fps / 2.0)))
    frames = []
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if index % interval == 0:
            resized = cv2.resize(frame, (0, 0), fx=0.5, fy=0.5)
            frames.append(cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY))
        index += 1
    cap.release()
    assert frames, 'No reference frames decoded'
    return frames


def decompress_entry(data):
    try:
        return zlib.decompress(data)
    except zlib.error:
        return zlib.decompress(data, 16 + zlib.MAX_WBITS)


def parse_archive(path):
    raw = open(path, 'rb').read()
    entries = []
    pos = 0
    while pos < len(raw):
        assert len(raw) - pos >= 2, 'Truncated path-length field'
        path_len = struct.unpack_from('<H', raw, pos)[0]
        pos += 2
        assert path_len > 0, 'Empty archive path'
        assert len(raw) - pos >= path_len + 4, 'Truncated archive entry header'
        path_bytes = raw[pos:pos + path_len]
        pos += path_len
        try:
            name = path_bytes.decode('utf-8')
        except UnicodeDecodeError as exc:
            raise AssertionError('Archive path is not UTF-8') from exc
        data_len = struct.unpack_from('<I', raw, pos)[0]
        pos += 4
        assert len(raw) - pos >= data_len, 'Truncated compressed data'
        compressed = raw[pos:pos + data_len]
        pos += data_len
        assert name == os.path.basename(name), 'Archive entry is not just a filename: ' + name
        assert name not in ('', '.', '..') and '\x00' not in name, 'Unsafe archive filename'
        try:
            payload = decompress_entry(compressed)
        except Exception as exc:
            raise AssertionError('Entry is not zlib/gzip compressed: ' + name) from exc
        entries.append((name, payload))
    assert pos == len(raw), 'Archive has unparsed trailing bytes'
    return entries


def assert_images_match(items, refs, label):
    assert len(items) == len(refs), f'{label} frame count {len(items)} != expected {len(refs)}'
    scores = []
    for (name, data), ref in zip(sorted(items, key=lambda x: natural_key(x[0])), refs):
        image = cv2.imdecode(__import__('numpy').frombuffer(data, dtype='uint8'), cv2.IMREAD_GRAYSCALE)
        assert image is not None, f'Invalid image data for {name}'
        assert image.shape == ref.shape, f'{name} has shape {image.shape}, expected {ref.shape}'
        scores.append(ssim(ref, image, data_range=255))
    average = sum(scores) / len(scores)
    assert average >= 0.90, f'Average {label} SSIM {average:.4f} is below 0.90'


def test_complete_archival_system():
    archive_script = find_script('archive.py')
    extract_script = find_script('extract.py')

    source = open(archive_script, encoding='utf-8').read()
    tree = ast.parse(source, filename=archive_script)
    uses_multiprocessing = any(
        (isinstance(node, ast.Import) and any(alias.name == 'multiprocessing' for alias in node.names)) or
        (isinstance(node, ast.ImportFrom) and node.module and node.module.startswith('multiprocessing'))
        for node in ast.walk(tree)
    )
    assert uses_multiprocessing, 'archive.py must use multiprocessing'

    for path in (ARCHIVE, RESTORED, '/home/user/malicious_test_file.txt',
                 '/tmp/archive_abs_attack.txt', '/tmp/archive_flock.log'):
        if os.path.lexists(path):
            remove_path(path)

    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/archive_instrument' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    result = subprocess.run(
        ['python3', archive_script], cwd=os.path.dirname(archive_script), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
    )
    assert result.returncode == 0, 'archive.py failed:\n' + result.stdout + result.stderr

    assert os.path.exists(ARCHIVE), 'Archive not found at /home/user/video_archive.bin'
    size = os.path.getsize(ARCHIVE)
    assert size <= 5242880, f'Archive size {size} exceeds 5MB threshold'
    assert size > 0, 'Archive is empty'

    lock_pids = set()
    if os.path.exists('/tmp/archive_flock.log'):
        for line in open('/tmp/archive_flock.log', encoding='ascii', errors='replace'):
            parts = line.split()
            if len(parts) == 3 and parts[0] == 'FLOCK':
                pid, operation = int(parts[1]), int(parts[2])
                if operation & 2:  # fcntl.LOCK_EX
                    lock_pids.add(pid)
    assert len(lock_pids) == 4, (
        'Exactly four worker processes must perform archive writes under POSIX exclusive flock; '
        f'observed locking PIDs: {sorted(lock_pids)}'
    )

    refs = reference_frames()
    entries = parse_archive(ARCHIVE)
    names = [name for name, _ in entries]
    assert len(entries) == len(refs), f'Archive contains {len(entries)} frames, expected {len(refs)}'
    assert len(names) == len(set(names)), 'Archive contains duplicate frame filenames'
    assert_images_match(entries, refs, 'archived-frame')

    # Append validly compressed traversal entries plus a safe probe. The safe entry
    # proves extract.py actually consumes the archive and continues past bad paths.
    attacks = [
        ('../malicious_test_file.txt', b'malicious content'),
        ('/tmp/archive_abs_attack.txt', b'absolute-path attack'),
        ('nested/../../../tmp/archive_abs_attack.txt', b'nested traversal attack'),
    ]
    probe = __import__('numpy').zeros((13, 17, 3), dtype='uint8')
    probe[:, :] = (17, 91, 203)
    ok, encoded = cv2.imencode('.png', probe)
    assert ok
    appended = attacks + [('zz_verifier_probe.png', encoded.tobytes())]
    with open(ARCHIVE, 'ab') as out:
        for name, payload in appended:
            path_bytes = name.encode('utf-8')
            compressed = zlib.compress(payload)
            out.write(struct.pack('<H', len(path_bytes)))
            out.write(path_bytes)
            out.write(struct.pack('<I', len(compressed)))
            out.write(compressed)

    if os.path.lexists(RESTORED):
        remove_path(RESTORED)
    extraction = subprocess.run(
        ['python3', extract_script], cwd=os.path.dirname(extract_script),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert extraction.returncode == 0, 'extract.py failed:\n' + extraction.stdout + extraction.stderr

    assert not os.path.exists('/home/user/malicious_test_file.txt'), \
        'Zip Slip vulnerability: traversal file was extracted outside the target directory'
    assert not os.path.exists('/tmp/archive_abs_attack.txt'), \
        'Zip Slip vulnerability: absolute/traversal file was extracted outside the target directory'
    warning_output = (extraction.stdout + extraction.stderr).lower()
    assert warning_output and any(word in warning_output for word in ('warn', 'skip', 'unsafe', 'malicious', 'traversal')), \
        'extract.py must print a warning when unsafe paths are skipped'

    assert os.path.isdir(RESTORED), 'Restored frames directory not found'
    probe_path = os.path.join(RESTORED, 'zz_verifier_probe.png')
    assert os.path.isfile(probe_path), 'extract.py did not extract the safe archive probe'
    assert open(probe_path, 'rb').read() == encoded.tobytes(), 'Safe probe was not restored exactly'

    restored_names = sorted(
        [name for name in os.listdir(RESTORED)
         if name.lower().endswith(('.png', '.jpg', '.jpeg')) and name != 'zz_verifier_probe.png'],
        key=natural_key
    )
    assert set(restored_names) == set(names), 'Restored frame set does not match all archived frames'
    restored_items = []
    for name in restored_names:
        path = os.path.join(RESTORED, name)
        assert os.path.isfile(path) and not os.path.islink(path), 'Restored frame is not a regular file: ' + name
        restored_items.append((name, open(path, 'rb').read()))
    assert_images_match(restored_items, refs, 'restored-frame')
PYEOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
