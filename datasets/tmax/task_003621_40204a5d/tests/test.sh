#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess
from pathlib import Path

HOME = Path('/home/user')
WHISPER = HOME / 'whisper'
AUDIO = Path('/app/voice_commands.wav')
WORDS = HOME / 'clean_words.txt'
REPORT = HOME / 'analysis_report.txt'
EXPECTED_WORDS = [
    'and', 'so', 'my', 'fellow', 'americans', 'ask', 'not', 'what',
    'your', 'country', 'can', 'do', 'for', 'you', 'ask', 'what', 'you',
    'can', 'do', 'for', 'your', 'country'
]


def alpha_words(text):
    return re.findall(r'[A-Za-z]+', text.lower())


def contains_sequence(words, expected):
    n = len(expected)
    return any(words[i:i+n] == expected for i in range(len(words) - n + 1))


def find_transcription():
    excluded = {WORDS.resolve(), REPORT.resolve()}
    for path in HOME.rglob('*.txt'):
        try:
            if path.resolve() in excluded or not path.is_file() or path.stat().st_size > 2_000_000:
                continue
            # A transcription must be prose rather than another one-word-per-line copy.
            text = path.read_text(errors='ignore')
            nonempty = [line.strip() for line in text.splitlines() if line.strip()]
            if nonempty and all(re.fullmatch(r'[A-Za-z]+', line) for line in nonempty):
                continue
            if contains_sequence(alpha_words(text), EXPECTED_WORDS):
                return path
        except (OSError, UnicodeError):
            pass
    return None


def find_bootstrap_scripts():
    found = []
    for path in HOME.rglob('*'):
        try:
            if not path.is_file() or path.stat().st_size > 1_000_000:
                continue
            data = path.read_bytes()
            if b'\x00' in data:
                continue
            source = data.decode(errors='ignore')
            if 'clean_words' not in source or not re.search(r'(?<!\d)5000(?!\d)', source):
                continue
            if path.suffix not in ('.sh', '.awk') and not source.startswith('#!'):
                continue
            found.append((path, source))
        except OSError:
            pass
    return found


def test_final_state():
    # Environment setup and a real compiled whisper.cpp executable/model.
    assert AUDIO.is_file(), 'The supplied audio file is missing.'
    assert WHISPER.is_dir(), '/home/user/whisper is missing.'
    assert (WHISPER / 'whisper.cpp').is_file(), 'The whisper.cpp source tree is missing.'

    model = WHISPER / 'models' / 'ggml-tiny.en.bin'
    assert model.is_file(), 'The tiny.en model was not downloaded with the provided model layout.'
    assert model.stat().st_size > 50_000_000, 'The tiny.en model is incomplete.'

    binary_candidates = [
        WHISPER / 'build' / 'bin' / 'whisper-cli',
        WHISPER / 'build' / 'bin' / 'main',
        WHISPER / 'main',
    ]
    binary = None
    for candidate in binary_candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            with candidate.open('rb') as f:
                if f.read(4) == b'\x7fELF':
                    binary = candidate
                    break
    assert binary is not None, 'No compiled ELF whisper-cli/main executable was found.'

    # The agent must have retained a prose transcription artifact for the supplied audio.
    transcription = find_transcription()
    assert transcription is not None, 'No text transcription of voice_commands.wav was found.'

    # Independently execute the submitted whisper build against the supplied audio.
    prefix = Path('/tmp/verifier_whisper_output')
    output_txt = Path(str(prefix) + '.txt')
    output_txt.unlink(missing_ok=True)
    run = subprocess.run(
        [str(binary), '-m', str(model), '-f', str(AUDIO), '-otxt', '-of', str(prefix)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=240,
    )
    assert run.returncode == 0, f'whisper.cpp failed to transcribe the supplied audio: {run.stdout[-1000:]}'
    generated = output_txt.read_text(errors='ignore') if output_txt.is_file() else run.stdout
    assert contains_sequence(alpha_words(generated), EXPECTED_WORDS), \
        'The compiled whisper.cpp/model did not produce the expected words from voice_commands.wav.'

    # Locate and execute the Bash/Awk bootstrap implementation.
    scripts = find_bootstrap_scripts()
    assert scripts, 'No Bash/Awk bootstrap script containing the required 5,000 repetitions was found.'
    executed = False
    errors = []
    for path, source in scripts:
        assert re.search(r'rand\s*\(', source) or re.search(r'\bshuf\b[^\n]*(?:-r|--repeat)', source), \
            f'{path} does not show sampling with replacement.'
        assert not re.search(r'(^|[;&|]\s*|\$\()\s*(python(?:3)?|perl|ruby|node|Rscript)\b', source, re.I | re.M), \
            f'{path} uses a prohibited high-level scripting language.'
        command = ['awk', '-f', str(path), str(WORDS)] if path.suffix == '.awk' else ['bash', str(path)]
        try:
            result = subprocess.run(
                command, cwd=str(path.parent), stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, timeout=180
            )
            if result.returncode == 0:
                executed = True
                break
            errors.append(f'{path}: exit {result.returncode}')
        except subprocess.TimeoutExpired:
            errors.append(f'{path}: timed out')
    assert executed, 'No submitted bootstrap script executed successfully: ' + '; '.join(errors)

    # Original file assertions and metric checks.
    assert WORDS.is_file(), 'The file /home/user/clean_words.txt is missing.'
    assert REPORT.is_file(), 'The file /home/user/analysis_report.txt is missing.'

    raw_lines = WORDS.read_text().splitlines()
    assert raw_lines, 'clean_words.txt is empty, no words extracted.'
    assert all(re.fullmatch(r'[a-z]+', line) for line in raw_lines), \
        'clean_words.txt must contain exactly one lowercase alphabetical word per line.'
    assert raw_lines == EXPECTED_WORDS, \
        'clean_words.txt does not contain the words spoken in voice_commands.wav.'

    lengths = [len(word) for word in raw_lines]
    actual_mean = sum(lengths) / len(lengths)
    sample_variance = sum((x - actual_mean) ** 2 for x in lengths) / (len(lengths) - 1)
    theoretical_sem = math.sqrt(sample_variance) / math.sqrt(len(lengths))

    content = REPORT.read_text()
    match = re.fullmatch(
        r'Mean_Length=([0-9]+\.[0-9]{4})\nBootstrap_SEM=([0-9]+\.[0-9]{4})\n?',
        content,
    )
    assert match, 'analysis_report.txt must contain exactly the requested two lines with four decimal places.'
    agent_mean = float(match.group(1))
    agent_sem = float(match.group(2))

    assert abs(agent_mean - actual_mean) < 0.01, \
        f'Reported Mean_Length {agent_mean} does not match the actual mean length {actual_mean:.4f}.'

    error = abs(agent_sem - theoretical_sem) / theoretical_sem
    score = max(0.0, 1.0 - (error / 0.10))
    assert score >= 0.8, \
        f'Score {score:.2f} is below threshold 0.8. Reported Bootstrap_SEM: {agent_sem}, Theoretical SEM: {theoretical_sem:.4f}, Relative Error: {error:.4f}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
