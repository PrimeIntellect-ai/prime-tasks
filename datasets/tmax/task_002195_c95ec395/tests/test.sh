#!/bin/bash
set +e
mkdir -p /logs/verifier

cat > /tmp/verify_pipeline.py <<'PY'
import csv
import fcntl
import json
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import jiwer

PROCESS = Path('/home/user/pipeline/process.go')
SUMMARY = Path('/home/user/pipeline/summary.json')
APP_AUDIO = Path('/app/interview.wav')
APP_CSV = Path('/app/segments.csv')
WHISPER_DIR = Path('/home/user/whisper.cpp')
WHISPER_MAIN = WHISPER_DIR / 'main'


def check_original_assertions():
    assert PROCESS.is_file(), f'The Go program is missing at {PROCESS}.'
    assert SUMMARY.is_file(), f'The summary.json file is missing at {SUMMARY}.'

    try:
        data = json.loads(SUMMARY.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f'Failed to parse summary.json: {exc}')

    assert 'speakers' in data, "The JSON must contain a 'speakers' key."
    ground_truth = {
        'Speaker_1': 'we are here today to discuss the new automation pipeline that will be deployed next week.',
        'Speaker_2': 'i have reviewed the initial design and the concurrency model looks solid.',
    }

    total_wer = 0.0
    for speaker, truth_text in ground_truth.items():
        assert speaker in data['speakers'], f'Missing {speaker} in output JSON.'
        hypothesis = data['speakers'][speaker].get('transcript', '').lower().strip()
        truth_clean = ''.join(c for c in truth_text if c.isalnum() or c.isspace())
        hyp_clean = ''.join(c for c in hypothesis if c.isalnum() or c.isspace())
        truth_clean = ' '.join(truth_clean.split())
        hyp_clean = ' '.join(hyp_clean.split())
        total_wer += jiwer.wer(truth_clean, hyp_clean)

    avg_wer = total_wer / len(ground_truth)
    assert avg_wer <= 0.20, f'Average WER too high: {avg_wer:.4f} > 0.20 threshold.'

    for speaker, info in data.get('speakers', {}).items():
        assert 'transcript' in info, f"Missing 'transcript' for {speaker}."
        assert 'word_count' in info, f"Missing 'word_count' for {speaker}."
        actual = len(info['transcript'].split())
        assert info['word_count'] == actual, (
            f'Word count mismatch for {speaker}. Computed {actual} from transcript, '
            f"but JSON reports {info['word_count']}."
        )


def write_executable(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def check_dynamic_result(expected):
    assert SUMMARY.is_file(), 'Executing process.go did not create summary.json.'
    data = json.loads(SUMMARY.read_text())
    assert isinstance(data, dict) and isinstance(data.get('speakers'), dict)
    speakers = data['speakers']
    assert set(speakers) == set(expected), 'Output contains missing or unexpected speakers.'
    for speaker, transcript in expected.items():
        info = speakers[speaker]
        assert info.get('transcript') == transcript, (
            f'Incorrect SegmentID ordering or aggregation for {speaker}: {info.get("transcript")!r}'
        )
        assert info.get('word_count') == len(transcript.split()), (
            f'Incorrect word_count for {speaker}.'
        )


def assert_chunks_removed(log_path):
    if not log_path.exists():
        raise AssertionError('The program never invoked ffmpeg.')
    chunks = [Path(line.strip()) for line in log_path.read_text().splitlines() if line.strip()]
    assert chunks, 'The program never extracted an audio chunk.'
    leftovers = [str(p) for p in chunks if p.exists()]
    assert not leftovers, f'Temporary audio chunks were not cleaned up: {leftovers}'


def main():
    check_original_assertions()

    assert WHISPER_DIR.is_dir(), 'whisper.cpp was not cloned into /home/user/whisper.cpp.'
    assert (WHISPER_DIR / '.git').exists(), 'The whisper.cpp directory is not a git clone.'
    assert WHISPER_MAIN.is_file(), 'The compiled whisper.cpp main binary is missing.'
    assert os.access(WHISPER_MAIN, os.X_OK), 'The whisper.cpp main binary is not executable.'
    models = list((WHISPER_DIR / 'models').glob('*tiny.en*.bin'))
    assert models, 'The downloaded tiny.en model is missing.'

    with tempfile.TemporaryDirectory(prefix='pipeline-verifier-') as td_name:
        td = Path(td_name)
        binary = td / 'process'
        build = subprocess.run(
            ['go', 'build', '-o', str(binary), str(PROCESS)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
        )
        assert build.returncode == 0, f'process.go does not compile:\n{build.stdout}'

        backups = {}
        for path in (APP_AUDIO, APP_CSV, SUMMARY):
            backup = td / ('backup-' + path.name)
            if path.exists():
                shutil.copy2(path, backup)
                backups[path] = backup

        main_backup = WHISPER_DIR / '.main.verifier-backup'
        os.replace(WHISPER_MAIN, main_backup)

        try:
            bindir = td / 'bin'
            bindir.mkdir()
            expected_windows = td / 'windows.tsv'
            transcript_map = td / 'transcripts.tsv'
            ffmpeg_log = td / 'ffmpeg.log'
            whisper_log = td / 'whisper.log'
            state_file = td / 'state'
            state_file.write_text('0 0\n')

            segments = [
                ('30', '3.0', '3.4', 'Dynamic_A', 'third amber'),
                ('10', '1.0', '1.4', 'Dynamic_A', 'first cedar'),
                ('40', '4.0', '4.4', 'Dynamic_B', 'green field'),
                ('20', '2.0', '2.4', 'Dynamic_B', 'blue river'),
                ('60', '6.0', '6.4', 'Dynamic_C', 'solo beacon'),
                ('50', '5.0', '5.4', 'Dynamic_A', 'last quartz'),
            ]
            expected_windows.write_text(''.join(f'{s}\t{e}\n' for _, s, e, _, _ in segments))
            transcript_map.write_text(''.join(f'{s}\t{text}\n' for _, s, _, _, text in segments))

            ffmpeg_script = r'''#!/usr/bin/env python3
import fcntl, os, sys
from pathlib import Path
args = sys.argv[1:]
input_path = None
start = None
end = None
duration = None
for i, arg in enumerate(args):
    if arg == '-i' and i + 1 < len(args): input_path = args[i + 1]
    if arg == '-ss' and i + 1 < len(args): start = float(args[i + 1])
    if arg == '-to' and i + 1 < len(args): end = float(args[i + 1])
    if arg == '-t' and i + 1 < len(args): duration = float(args[i + 1])
if input_path != '/app/interview.wav' or start is None:
    sys.exit(21)
if end is None and duration is not None:
    end = start + duration
if end is None:
    sys.exit(22)
allowed = set()
for line in Path(os.environ['VERIFY_WINDOWS']).read_text().splitlines():
    a, b = line.split('\t')
    allowed.add((round(float(a), 6), round(float(b), 6)))
if (round(start, 6), round(end, 6)) not in allowed:
    sys.exit(23)
out = Path(args[-1])
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(f'{start:.6f}|{end:.6f}\n')
with open(os.environ['VERIFY_FFMPEG_LOG'], 'a') as log:
    fcntl.flock(log, fcntl.LOCK_EX)
    log.write(str(out) + '\n')
    log.flush()
sys.exit(0)
'''
            write_executable(bindir / 'ffmpeg', ffmpeg_script)

            whisper_script = r'''#!/usr/bin/env python3
import fcntl, os, sys, time
from pathlib import Path

def update(delta):
    state = Path(os.environ['VERIFY_STATE'])
    with state.open('r+') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        parts = f.read().split()
        current, maximum = (int(parts[0]), int(parts[1])) if len(parts) == 2 else (0, 0)
        current += delta
        maximum = max(maximum, current)
        f.seek(0); f.truncate(); f.write(f'{current} {maximum}\n'); f.flush()
        return current, maximum

args = sys.argv[1:]
audio = None
prefix = None
for i, arg in enumerate(args):
    if arg == '-f' and i + 1 < len(args): audio = args[i + 1]
    if arg == '-of' and i + 1 < len(args): prefix = args[i + 1]
if audio is None:
    for arg in args:
        if arg.lower().endswith('.wav'):
            audio = arg
if audio is None:
    sys.exit(31)
marker = Path(audio).read_text().strip()
start = marker.split('|')[0]
start_key = str(float(start))
mapping = {}
for line in Path(os.environ['VERIFY_TRANSCRIPTS']).read_text().splitlines():
    key, text = line.split('\t', 1)
    mapping[str(float(key))] = text
if start_key not in mapping:
    sys.exit(32)
with open(os.environ['VERIFY_WHISPER_LOG'], 'a') as log:
    fcntl.flock(log, fcntl.LOCK_EX); log.write(start_key + '\n'); log.flush()
update(1)
try:
    time.sleep(0.45)
    if os.environ.get('VERIFY_FAIL_START') == start_key:
        sys.exit(37)
    text = mapping[start_key]
    if '-otxt' in args:
        Path(audio + '.txt').write_text(text + '\n')
    if prefix is not None:
        Path(prefix + '.txt').write_text(text + '\n')
    print(text)
finally:
    update(-1)
'''
            write_executable(WHISPER_MAIN, whisper_script)

            APP_AUDIO.write_text('verifier-controlled input; ffmpeg wrapper must extract it\n')
            with APP_CSV.open('w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['SegmentID', 'StartTime', 'EndTime', 'SpeakerID'])
                for sid, start, end, speaker, _ in segments:
                    writer.writerow([sid, start, end, speaker])
            if SUMMARY.exists():
                SUMMARY.unlink()

            env = os.environ.copy()
            env['PATH'] = str(bindir) + os.pathsep + env.get('PATH', '')
            env['VERIFY_WINDOWS'] = str(expected_windows)
            env['VERIFY_TRANSCRIPTS'] = str(transcript_map)
            env['VERIFY_FFMPEG_LOG'] = str(ffmpeg_log)
            env['VERIFY_WHISPER_LOG'] = str(whisper_log)
            env['VERIFY_STATE'] = str(state_file)

            run = subprocess.run(
                [str(binary)], cwd='/home/user/pipeline', env=env,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45,
            )
            assert run.returncode == 0, f'Pipeline failed on generated segments:\n{run.stdout}'
            assert len(ffmpeg_log.read_text().splitlines()) == len(segments), (
                'Each CSV segment must be extracted exactly once with ffmpeg.'
            )
            assert len(whisper_log.read_text().splitlines()) == len(segments), (
                'Each extracted segment must be transcribed exactly once with whisper.cpp.'
            )
            current, maximum = map(int, state_file.read_text().split())
            assert current == 0
            assert 2 <= maximum <= 4, (
                f'Observed {maximum} concurrent transcriptions; expected concurrent processing '
                'with a hard limit of 4.'
            )
            check_dynamic_result({
                'Dynamic_A': 'first cedar third amber last quartz',
                'Dynamic_B': 'blue river green field',
                'Dynamic_C': 'solo beacon',
            })
            assert_chunks_removed(ffmpeg_log)

            # Exercise error propagation and cleanup with a forced transcription failure.
            ffmpeg_log.write_text('')
            whisper_log.write_text('')
            state_file.write_text('0 0\n')
            with APP_CSV.open('w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['SegmentID', 'StartTime', 'EndTime', 'SpeakerID'])
                writer.writerow(['20', '2.0', '2.4', 'FailureSpeaker'])
            if SUMMARY.exists():
                SUMMARY.unlink()
            env['VERIFY_FAIL_START'] = '2.0'
            failed = subprocess.run(
                [str(binary)], cwd='/home/user/pipeline', env=env,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
            )
            assert failed.returncode != 0, 'A whisper.cpp failure was silently treated as success.'
            assert_chunks_removed(ffmpeg_log)
        finally:
            if WHISPER_MAIN.exists() or WHISPER_MAIN.is_symlink():
                WHISPER_MAIN.unlink()
            if main_backup.exists():
                os.replace(main_backup, WHISPER_MAIN)
            for path in (APP_AUDIO, APP_CSV, SUMMARY):
                if path.exists():
                    path.unlink()
                if path in backups:
                    shutil.copy2(backups[path], path)


if __name__ == '__main__':
    main()
PY

python3 /tmp/verify_pipeline.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
