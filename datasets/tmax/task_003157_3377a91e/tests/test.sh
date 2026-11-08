#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import difflib
import importlib.util
import math
import os
import shutil
import string
import subprocess
import sys
import tempfile
import wave
from collections import Counter
from pathlib import Path

from importlib import metadata
from packaging.requirements import Requirement
from scapy.all import Raw, rdpcap

SERVICE = Path('/app/transcriber_service')


def calculate_similarity(file_path, ground_truth):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            prediction = f.read().lower().strip()
        prediction = prediction.translate(str.maketrans('', '', string.punctuation))
        truth = ground_truth.translate(str.maketrans('', '', string.punctuation))
        return difflib.SequenceMatcher(None, prediction.split(), truth.split()).ratio()
    except FileNotFoundError:
        return 0.0


def test_transcript_similarity():
    target_path = '/home/user/transcript.txt'
    assert os.path.isfile(target_path), f'Target transcript file {target_path} does not exist.'
    truth_text = 'the server infrastructure migration is scheduled for next tuesday at midnight ensure all database backups are verified before initiating the sequence'
    score = calculate_similarity(target_path, truth_text)
    threshold = 0.85
    assert score >= threshold, f'Transcription similarity score {score:.4f} is below the required threshold of {threshold:.4f}.'


def test_requirements_were_corrected_and_are_installed_consistently():
    path = SERVICE / 'requirements.txt'
    assert path.is_file()
    lines = [line.strip() for line in path.read_text().splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    original = {
        'requests==2.25.1',
        'urllib3==1.26.5',
        'chardet==3.0.4',
        'idna==2.10',
    }
    assert set(lines) != original, 'requirements.txt was not corrected'

    requirements = [Requirement(line) for line in lines]
    for req in requirements:
        if req.marker and not req.marker.evaluate():
            continue
        installed = metadata.version(req.name)
        assert not req.specifier or req.specifier.contains(installed, prereleases=True), \
            f'{req.name} {installed} does not satisfy {req.specifier}'

    # Check the installed dependencies declared by each requested distribution too.
    for req in requirements:
        if req.marker and not req.marker.evaluate():
            continue
        dist = metadata.distribution(req.name)
        for dependency_text in dist.requires or []:
            dependency = Requirement(dependency_text)
            if dependency.marker and not dependency.marker.evaluate():
                continue
            try:
                installed = metadata.version(dependency.name)
            except metadata.PackageNotFoundError:
                raise AssertionError(f'Missing dependency {dependency.name} required by {req.name}')
            assert not dependency.specifier or dependency.specifier.contains(installed, prereleases=True), \
                f'{dependency.name} {installed} conflicts with {req.name} requirement {dependency.specifier}'


def test_fast_filter_is_fixed_built_and_installed():
    source_dir = SERVICE / 'fast_filter'
    setup_path = source_dir / 'setup.py'
    filter_path = source_dir / 'filter.c'
    assert setup_path.is_file() and filter_path.is_file()

    tree = ast.parse(setup_path.read_text())
    links_math = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            for keyword in node.keywords:
                if keyword.arg == 'libraries' and isinstance(keyword.value, (ast.List, ast.Tuple)):
                    values = [item.value for item in keyword.value.elts
                              if isinstance(item, ast.Constant) and isinstance(item.value, str)]
                    if 'm' in values:
                        links_math = True
    assert links_math, 'The extension configuration still does not link libm'

    # It must already be installed for a normal interpreter, not merely buildable by the verifier.
    env = os.environ.copy()
    env.pop('PYTHONPATH', None)
    installed_check = subprocess.run(
        [sys.executable, '-c',
         'import fast_filter, math; '
         'v=fast_filter.apply_filter(0.37); '
         'assert abs(v-math.sin(0.37)*math.cos(0.37)) < 1e-12'],
        cwd='/tmp', env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert installed_check.returncode == 0, 'fast_filter is not correctly installed: ' + installed_check.stderr

    # Also rebuild from clean source so a stale/prebuilt binary cannot satisfy the test.
    with tempfile.TemporaryDirectory() as temp:
        build_dir = Path(temp) / 'fast_filter'
        shutil.copytree(source_dir, build_dir, ignore=shutil.ignore_patterns('build', '*.so', '*.o', '__pycache__'))
        result = subprocess.run(
            [sys.executable, 'setup.py', 'build_ext', '--inplace'], cwd=build_dir,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert result.returncode == 0, 'Clean extension build failed: ' + result.stderr
        built_env = env.copy()
        built_env['PYTHONPATH'] = str(build_dir)
        result = subprocess.run(
            [sys.executable, '-c',
             'import fast_filter, math; '
             'assert abs(fast_filter.apply_filter(0.73)-math.sin(0.73)*math.cos(0.73)) < 1e-12; '
             'assert fast_filter.__file__.startswith(r"' + str(build_dir) + '")'],
            cwd=build_dir, env=built_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert result.returncode == 0, 'Cleanly built extension is unusable: ' + result.stderr


def test_cancelled_chunk_tasks_are_awaited_and_cleaned_up():
    main_path = SERVICE / 'main.py'
    assert main_path.is_file()
    spec = importlib.util.spec_from_file_location('submitted_transcriber_main', main_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    created = []
    original_create_task = asyncio.create_task

    def tracking_create_task(coro, *args, **kwargs):
        task = original_create_task(coro, *args, **kwargs)
        created.append(task)
        return task

    async def probe():
        module.asyncio.create_task = tracking_create_task
        try:
            await module.main()
            # Check immediately, before the verifier gives pending cancellations an extra loop turn.
            assert created, 'main() did not create any chunk-processing tasks'
            assert all(task.done() for task in created), 'main() returned with cancelled tasks not awaited'
            assert all(task.cancelled() or task.exception() is None for task in created)
        finally:
            module.asyncio.create_task = original_create_task
            for task in created:
                if not task.done():
                    task.cancel()
            if created:
                await asyncio.gather(*created, return_exceptions=True)

    asyncio.run(probe())


def derive_key_from_capture():
    capture = SERVICE / 'capture.pcap'
    assert capture.is_file()
    packets = rdpcap(str(capture))
    payloads = [bytes(packet[Raw].load) for packet in packets if Raw in packet and bytes(packet[Raw].load)]
    assert payloads, 'No payloads found in capture.pcap'
    counts = Counter(payload[0] for payload in payloads)
    key, repetitions = counts.most_common(1)[0]
    assert repetitions >= 2, 'No repeating malformed packet sequence was identified'
    return key


def valid_wav_bytes(path):
    try:
        with wave.open(str(path), 'rb') as audio:
            return audio.getnframes() > audio.getframerate() and audio.getnchannels() >= 1
    except (wave.Error, EOFError, OSError):
        return False


def test_pcap_key_and_audio_repair_artifacts():
    key = derive_key_from_capture()
    source = Path('/app/voicemail.wav')
    assert source.is_file()
    current = source.read_bytes()

    roots = [Path('/app'), Path('/home/user')]
    python_files = []
    wav_files = []
    for root in roots:
        for directory, _, files in os.walk(root):
            for name in files:
                path = Path(directory) / name
                if name.endswith('.py'):
                    python_files.append(path)
                if name.lower().endswith('.wav'):
                    wav_files.append(path)

    # The instruction explicitly requires a short repair script. It must implement XOR
    # and either consume the capture or contain the key derived from it.
    repair_scripts = []
    key_spellings = {str(key), hex(key).lower(), hex(key).upper().replace('X', 'x')}
    for path in python_files:
        try:
            text = path.read_text(errors='ignore')
        except OSError:
            continue
        lowered = text.lower()
        if '.wav' in lowered and ('^' in text or 'xor' in lowered):
            if 'capture.pcap' in lowered or any(spelling in text for spelling in key_spellings):
                repair_scripts.append(path)
    assert repair_scripts, 'No Python audio-repair script using the pcap-derived XOR key was found'

    # Accept either an in-place repair or a separately saved repaired WAV. If the
    # original remains obfuscated, require exact byte-for-byte XOR repair.
    repaired = []
    if current.startswith(b'RIFF') and valid_wav_bytes(source):
        repaired.append(source)
    else:
        expected = bytes(byte ^ key for byte in current)
        assert expected.startswith(b'RIFF') and expected[8:12] == b'WAVE', \
            'The repeating pcap value does not correctly repair the supplied voicemail'
        for path in wav_files:
            try:
                if path.read_bytes() == expected and valid_wav_bytes(path):
                    repaired.append(path)
            except OSError:
                pass
    assert repaired, 'No valid WAV produced by applying the pcap-derived XOR key was found'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
