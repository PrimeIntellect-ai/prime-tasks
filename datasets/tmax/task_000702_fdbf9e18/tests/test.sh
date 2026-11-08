#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import secrets
import stat
import subprocess


def levenshtein_distance(s1, s2):
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def compute_cer(reference, hypothesis):
    ref_len = len(reference)
    if ref_len == 0:
        return 1.0
    return levenshtein_distance(reference, hypothesis) / ref_len


def test_transcription_accuracy():
    transcript_path = '/home/user/transcripts/voicemail.txt'
    assert os.path.exists(transcript_path), f"Transcript file not found at {transcript_path}"

    ground_truth = "the disk quota has been exceeded on the primary storage volume please allocate additional drives to the raid array immediately to prevent data loss"

    with open(transcript_path, 'r') as f:
        agent_text = f.read().strip().lower()

    for char in ".,!?":
        agent_text = agent_text.replace(char, "")

    cer = compute_cer(ground_truth, agent_text)
    assert cer <= 0.15, f"Transcription CER is {cer:.3f}, which exceeds the threshold of 0.15. Ground truth: '{ground_truth}', Agent output: '{agent_text}'"


def test_archived_server_1_log():
    archive_path = '/home/user/archive_dir/server_1.log.gz'
    assert os.path.exists(archive_path), f"Archived file not found at {archive_path}"

    with gzip.open(archive_path, 'rt') as f:
        content = f.read()

    assert "[DEBUG]" not in content, f"[DEBUG] lines were not filtered out in {archive_path}"
    assert "[ERROR]" in content, f"[ERROR] lines were incorrectly filtered out in {archive_path}"
    assert "[INFO]" in content, f"[INFO] lines were incorrectly filtered out in {archive_path}"


def test_archived_app_server_log():
    archive_path = '/home/user/archive_dir/app_server.log.gz'
    assert os.path.exists(archive_path), f"Archived file not found at {archive_path}"

    with gzip.open(archive_path, 'rt') as f:
        content = f.read()

    assert "[DEBUG]" not in content, f"[DEBUG] lines were not filtered out in {archive_path}"
    assert "[INFO] App started" in content, f"Expected content missing in {archive_path}"
    assert "[INFO] Connected to DB" in content, f"Expected content missing in {archive_path}"


def uncommented_shell_text(text):
    cleaned = []
    for line in text.splitlines():
        out = []
        single = False
        double = False
        escaped = False
        for i, char in enumerate(line):
            if escaped:
                out.append(char)
                escaped = False
                continue
            if char == '\\' and not single:
                out.append(char)
                escaped = True
                continue
            if char == "'" and not double:
                single = not single
                out.append(char)
                continue
            if char == '"' and not single:
                double = not double
                out.append(char)
                continue
            if char == '#' and not single and not double and (i == 0 or line[i - 1].isspace()):
                break
            out.append(char)
        cleaned.append(''.join(out))
    result = '\n'.join(cleaned)
    result = re.sub(r'\\\s*\n', ' ', result)
    result = re.sub(r'\|\s*\n\s*', '| ', result)
    return result


def test_bash_script_exists_and_processes_unseen_logs():
    script_path = '/home/user/archive.sh'
    assert os.path.exists(script_path), f"Bash script not found at {script_path}"
    mode = os.stat(script_path, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"Bash script path is not a regular file: {script_path}"

    syntax = subprocess.run(
        ['bash', '-n', script_path], text=True, capture_output=True, timeout=10
    )
    assert syntax.returncode == 0, f"archive.sh is not valid Bash: {syntax.stderr}"

    with open(script_path, 'r', errors='replace') as f:
        script_text = f.read()
    active_text = uncommented_shell_text(script_text)
    assert re.search(r'\|\s*(?:command\s+)?(?:/[^\s|]+/)?gzip\b', active_text), \
        "archive.sh does not contain an active pipeline directly into gzip"

    token = secrets.token_hex(8)
    cases = {
        f'audit {token} one.log': (
            f'[INFO] begin-{token}\n'
            f'[DEBUG] secret-{token}\n'
            f'[ERROR] end-{token}\n'
        ),
        f'bulk  rename {token}.log': (
            f'plain-{token}\n'
            f'prefix [DEBUG] remove-{token}\n'
            f'[WARN] retain-{token}\n'
        ),
    }

    expected = {}
    for original_name, content in cases.items():
        source = os.path.join('/home/user/syslogs', original_name)
        renamed_name = original_name.replace(' ', '_')
        archive = os.path.join('/home/user/archive_dir', renamed_name + '.gz')
        for path in (source, os.path.join('/home/user/syslogs', renamed_name), archive):
            if os.path.exists(path):
                os.remove(path)
        with open(source, 'w') as f:
            f.write(content)
        expected[original_name] = (
            os.path.join('/home/user/syslogs', renamed_name),
            archive,
            ''.join(line for line in content.splitlines(True) if '[DEBUG]' not in line),
        )

    wrapper_dir = f'/tmp/gzip-wrapper-{token}'
    os.mkdir(wrapper_dir)
    trace_path = os.path.join(wrapper_dir, 'stdin-trace')
    wrapper_path = os.path.join(wrapper_dir, 'gzip')
    with open(wrapper_path, 'w') as f:
        f.write('#!/bin/bash\nreadlink /proc/$$/fd/0 >> "$GZIP_STDIN_TRACE"\nexec /usr/bin/gzip "$@"\n')
    os.chmod(wrapper_path, 0o755)

    env = os.environ.copy()
    env['PATH'] = wrapper_dir + ':' + env.get('PATH', '')
    env['GZIP_STDIN_TRACE'] = trace_path
    run = subprocess.run(
        ['bash', script_path], text=True, capture_output=True, timeout=30, env=env
    )
    assert run.returncode == 0, \
        f"archive.sh failed when executed (exit {run.returncode}):\nstdout: {run.stdout}\nstderr: {run.stderr}"

    for original_name, (renamed_source, archive, wanted) in expected.items():
        original_source = os.path.join('/home/user/syslogs', original_name)
        assert not os.path.exists(original_source), f"Log was not renamed: {original_source}"
        assert os.path.isfile(renamed_source), f"Renamed log not found: {renamed_source}"
        assert os.path.isfile(archive), f"Archive for dynamically added log not found: {archive}"
        with gzip.open(archive, 'rt') as f:
            actual = f.read()
        assert actual == wanted, \
            f"Archive {archive} did not exactly preserve non-debug lines. Expected {wanted!r}, got {actual!r}"

    if os.path.exists(trace_path):
        with open(trace_path, 'r') as f:
            gzip_inputs = [line.strip() for line in f if line.strip()]
        assert gzip_inputs, "gzip wrapper was invoked but recorded no input descriptors"
        assert all(item.startswith('pipe:[') for item in gzip_inputs), \
            f"gzip was invoked with non-pipeline input: {gzip_inputs}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
