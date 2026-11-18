#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import array
import json
import math
import os
import posixpath
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

EXTRACT_ROOT = '/home/user/update_extracted'
BACKUP_PATH = '/home/user/incremental_backup.tar.gz'
LOG_PATH = '/home/user/backup_files.log'
SNAPSHOT_PATH = '/app/backup.snar'
OGG_PATH = '/home/user/compressed_memo.ogg'
WAV_PATH = '/app/voice_memo.wav'


def normalized_member(name):
    name = name.replace('\\', '/')
    while name.startswith('./'):
        name = name[2:]
    return name.rstrip('/')


def test_zip_slip_prevented():
    assert not os.path.exists('/tmp/hacked.txt'), "Zip slip vulnerability was not prevented; /tmp/hacked.txt exists."

    root = os.path.realpath(EXTRACT_ROOT)
    assert os.path.isdir(root), f"{EXTRACT_ROOT} is not a directory."

    with zipfile.ZipFile('/app/update.zip') as archive:
        for info in archive.infolist():
            name = info.filename.replace('\\', '/')
            parts = [part for part in name.split('/') if part not in ('', '.')]
            safe = not name.startswith('/') and '..' not in parts
            destination = os.path.realpath(os.path.join(root, name))

            if safe:
                assert os.path.commonpath([root, destination]) == root, f"Safe member escaped extraction root: {name}"
                if not info.is_dir():
                    assert os.path.isfile(destination), f"Safe archive member was not extracted: {name}"
                    with archive.open(info) as expected, open(destination, 'rb') as actual:
                        assert actual.read() == expected.read(), f"Extracted contents differ for {name}"
            elif os.path.commonpath([root, destination]) != root:
                assert not os.path.lexists(destination), f"Unsafe archive member escaped to {destination}"

    for current, directories, files in os.walk(root, followlinks=False):
        for entry in directories + files:
            path = os.path.join(current, entry)
            assert not os.path.islink(path), f"Extraction created a symbolic link: {path}"
            assert os.path.commonpath([root, os.path.realpath(path)]) == root, f"Extracted path escapes target: {path}"


def test_settings_extracted_correctly():
    settings_path = '/home/user/update_extracted/settings.conf'
    assert os.path.exists(settings_path), f"{settings_path} does not exist."
    with open(settings_path, 'r') as f:
        content = f.read()
    assert 'TargetDirectory=/app/data_dir' in content, f"Expected 'TargetDirectory=/app/data_dir' in {settings_path}, but got: {content}"

    with zipfile.ZipFile('/app/update.zip') as archive:
        expected = archive.read('settings.conf')
    with open(settings_path, 'rb') as extracted:
        assert extracted.read() == expected, 'settings.conf is not the file supplied in update.zip.'


def read_target_directory():
    with open('/home/user/update_extracted/settings.conf', encoding='utf-8') as config:
        for line in config:
            key, separator, value = line.partition('=')
            if separator and key.strip() == 'TargetDirectory':
                return os.path.realpath(value.strip())
    raise AssertionError('TargetDirectory was not found in settings.conf.')


def test_incremental_backup_created():
    backup_path = BACKUP_PATH
    assert os.path.exists(backup_path), f"{backup_path} does not exist."
    assert tarfile.is_tarfile(backup_path), f"{backup_path} is not a valid tar file."

    target = read_target_directory()
    assert target == '/app/data_dir', f'Unexpected backup target: {target}'

    with tarfile.open(backup_path, 'r:gz') as tar:
        names = tar.getnames()
        assert any('file2.txt' in name for name in names), "Incremental backup does not contain the new file 'file2.txt'."

        regular_files = []
        for member in tar.getmembers():
            name = normalized_member(member.name)
            assert name and not name.startswith('/') and '..' not in name.split('/'), f'Unsafe tar member: {member.name}'
            assert not member.issym() and not member.islnk(), f'Backup contains a link instead of target data: {member.name}'
            if not member.isfile():
                continue

            if name.startswith('data_dir/'):
                relative = name[len('data_dir/'):]
            else:
                relative = name
            source = os.path.realpath(os.path.join(target, relative))
            assert os.path.commonpath([target, source]) == target, f'Tar member is outside TargetDirectory: {member.name}'
            assert os.path.isfile(source), f'Tar member does not come from TargetDirectory: {member.name}'
            extracted = tar.extractfile(member)
            assert extracted is not None
            with extracted, open(source, 'rb') as expected:
                assert extracted.read() == expected.read(), f'Backup content differs from source for {member.name}'
            regular_files.append(relative)

        assert 'file2.txt' in regular_files, "The exact target file file2.txt is absent from the incremental backup."
        file2_member = next(m for m in tar.getmembers() if m.isfile() and normalized_member(m.name).split('/')[-1] == 'file2.txt')
        assert tar.extractfile(file2_member).read() == b'new data\n', 'file2.txt has incorrect backup contents.'


def test_snapshot_was_updated_and_is_usable():
    assert os.path.isfile(SNAPSHOT_PATH), f'{SNAPSHOT_PATH} is missing.'
    with open(SNAPSHOT_PATH, 'rb') as snapshot:
        snapshot_data = snapshot.read()
    assert snapshot_data.startswith(b'GNU tar-'), 'backup.snar is not a GNU tar listed-incremental snapshot.'
    assert b'file2.txt' in snapshot_data, 'backup.snar was not updated to record file2.txt.'

    target = read_target_directory()
    with tarfile.open(BACKUP_PATH, 'r:gz') as submitted:
        submitted_names = [normalized_member(name) for name in submitted.getnames()]
    rooted_style = any(name == 'data_dir' or name.startswith('data_dir/') for name in submitted_names)

    with tempfile.TemporaryDirectory() as temporary:
        snapshot_copy = os.path.join(temporary, 'probe.snar')
        empty_probe = os.path.join(temporary, 'unchanged.tar.gz')
        changed_probe = os.path.join(temporary, 'changed.tar.gz')
        shutil.copyfile(SNAPSHOT_PATH, snapshot_copy)

        if rooted_style:
            command_base = ['tar', f'--listed-incremental={snapshot_copy}', '-czf']
            location = ['-C', os.path.dirname(target), os.path.basename(target)]
        else:
            command_base = ['tar', f'--listed-incremental={snapshot_copy}', '-czf']
            location = ['-C', target, '.']

        subprocess.run(command_base + [empty_probe] + location, check=True, capture_output=True)
        with tarfile.open(empty_probe, 'r:gz') as probe:
            unchanged_regular = [m.name for m in probe.getmembers() if m.isfile()]
        assert not unchanged_regular, f'backup.snar does not describe the current target state; it re-backed up {unchanged_regular}'

        canary_name = '.verifier_incremental_' + uuid.uuid4().hex
        canary_path = os.path.join(target, canary_name)
        canary_data = os.urandom(37)
        try:
            with open(canary_path, 'wb') as canary:
                canary.write(canary_data)
            subprocess.run(command_base + [changed_probe] + location, check=True, capture_output=True)
            with tarfile.open(changed_probe, 'r:gz') as probe:
                matches = [m for m in probe.getmembers() if m.isfile() and normalized_member(m.name).split('/')[-1] == canary_name]
                assert len(matches) == 1, 'The updated snapshot did not detect a newly changed target file.'
                assert probe.extractfile(matches[0]).read() == canary_data
        finally:
            if os.path.exists(canary_path):
                os.unlink(canary_path)


def test_backup_log_created():
    log_path = LOG_PATH
    assert os.path.exists(log_path), f"{log_path} does not exist."
    with open(log_path, 'r') as f:
        content = f.read()
    assert len(content.strip()) > 0, f"{log_path} is empty."

    with tarfile.open(BACKUP_PATH, 'r:gz') as archive:
        archive_names = {normalized_member(name) for name in archive.getnames() if normalized_member(name)}
    log_names = {normalized_member(line.strip()) for line in content.splitlines() if normalized_member(line.strip())}
    assert log_names == archive_names, f'backup_files.log is not the actual tar member listing: log={log_names}, archive={archive_names}'


def probe(path):
    result = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'format=format_name,duration:stream=codec_name,codec_type,duration', '-of', 'json', path],
        check=True, capture_output=True, text=True
    )
    return json.loads(result.stdout)


def decode_audio(path):
    result = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', path, '-map', '0:a:0', '-ac', '1', '-ar', '8000', '-f', 'f32le', '-'],
        check=True, capture_output=True
    )
    samples = array.array('f')
    samples.frombytes(result.stdout)
    return list(samples)


def duration(metadata):
    for stream in metadata.get('streams', []):
        if stream.get('codec_type') == 'audio' and stream.get('duration') not in (None, 'N/A'):
            return float(stream['duration'])
    return float(metadata['format']['duration'])


def best_correlation(reference, candidate):
    reference = reference[::8]
    candidate = candidate[::8]
    best = -1.0
    for shift in range(-200, 201):
        if shift >= 0:
            left = reference[shift:]
            right = candidate[:len(left)]
        else:
            right = candidate[-shift:]
            left = reference[:len(right)]
        count = min(len(left), len(right))
        if count < 5000:
            continue
        left = left[:count]
        right = right[:count]
        mean_left = sum(left) / count
        mean_right = sum(right) / count
        covariance = sum((a - mean_left) * (b - mean_right) for a, b in zip(left, right))
        power_left = sum((a - mean_left) ** 2 for a in left)
        power_right = sum((b - mean_right) ** 2 for b in right)
        if power_left and power_right:
            best = max(best, covariance / math.sqrt(power_left * power_right))
    return best


def test_audio_compression_metric():
    ogg_path = OGG_PATH
    assert os.path.exists(ogg_path), f"Compressed audio file {ogg_path} does not exist."
    size = os.path.getsize(ogg_path)

    try:
        subprocess.run(["ffprobe", "-v", "error", ogg_path], check=True, capture_output=True)
        valid = True
    except subprocess.CalledProcessError as e:
        valid = False
        assert False, f"ffprobe failed to validate {ogg_path} as a valid media file. Error: {e.stderr.decode()}"

    assert valid, f"{ogg_path} is not a valid decodable file."
    assert size <= 15000, f"File size of {ogg_path} is {size} bytes, which exceeds the threshold of 15000 bytes."

    output_metadata = probe(ogg_path)
    input_metadata = probe(WAV_PATH)
    audio_streams = [s for s in output_metadata.get('streams', []) if s.get('codec_type') == 'audio']
    assert len(audio_streams) == 1, 'Output must contain exactly one audio stream.'
    assert audio_streams[0].get('codec_name') == 'vorbis', 'Output audio codec is not Ogg Vorbis.'
    assert 'ogg' in output_metadata.get('format', {}).get('format_name', '').split(','), 'Output container is not Ogg.'
    assert abs(duration(output_metadata) - duration(input_metadata)) <= 0.15, 'Compressed audio duration differs from voice_memo.wav.'

    reference = decode_audio(WAV_PATH)
    candidate = decode_audio(ogg_path)
    assert abs(len(candidate) - len(reference)) <= 1200, 'Decoded output length differs from the supplied WAV.'
    correlation = best_correlation(reference, candidate)
    assert correlation >= 0.90, f'Compressed audio does not represent voice_memo.wav (correlation {correlation:.3f}).'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
