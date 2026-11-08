#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path

VIDEO = Path('/app/build_capture.mp4')
DEPS = Path('/home/user/project/deps.txt')
SCRIPT = Path('/home/user/organize.sh')


def derive_corruption_from_video():
    with tempfile.TemporaryDirectory() as tmp:
        pattern = os.path.join(tmp, 'frame_%06d.png')
        subprocess.run(
            [
                'ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(VIDEO),
                '-vf', 'format=rgb24,extractplanes=r,scale=1280:960:flags=neighbor',
                pattern,
            ],
            check=True,
            timeout=20,
        )

        matches = []
        for image in sorted(Path(tmp).glob('frame_*.png')):
            result = subprocess.run(
                ['tesseract', str(image), 'stdout', '--psm', '6'],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=True,
                timeout=5,
            )
            compact = re.sub(r'\s+', '', result.stdout)
            match = re.search(r'CORRUPTION_DETECTED[:;]([A-Za-z0-9_]+)', compact)
            if match:
                frame_number = int(image.stem.rsplit('_', 1)[1])
                matches.append((frame_number, match.group(1)))

        assert matches, 'Verifier OCR could not locate CORRUPTION_DETECTED in the video'
        assert len(matches) == 1, f'Expected one corrupt frame, OCR found {matches}'
        return matches[0]


def derive_impacted(module):
    graph = {}
    for raw_line in DEPS.read_text().splitlines():
        line = raw_line.strip()
        if not line:
            continue
        name, separator, dependencies = line.partition(':')
        assert separator, f'Invalid dependency line: {raw_line!r}'
        graph[name.strip()] = dependencies.split()

    visited = set()
    pending = list(graph.get(module, []))
    while pending:
        dependency = pending.pop()
        if dependency == module or dependency in visited:
            continue
        visited.add(dependency)
        pending.extend(graph.get(dependency, []))
    return sorted(visited)


def expected_report():
    frame, module = derive_corruption_from_video()
    impacted = derive_impacted(module)
    checksum_text = ''.join(impacted)
    return {
        'corrupt_frame': frame,
        'corrupt_module': module,
        'impacted_deps': impacted,
        'ascii_sum': sum(ord(character) for character in checksum_text),
    }


def test_websocket_server_response():
    expected = expected_report()
    proc = subprocess.Popen(
        ['websocat', 'ws://127.0.0.1:8081'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        stdout, stderr = proc.communicate(input='GET_REPORT\n', timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()

    output = stdout.strip()
    assert output, f'WebSocket server did not return any output. stderr: {stderr}'
    last_line = output.splitlines()[-1]
    try:
        data = json.loads(last_line)
    except json.JSONDecodeError as error:
        raise AssertionError(f'WebSocket response is not valid JSON: {last_line}') from error

    assert set(data) == set(expected), f'Response must contain exactly {list(expected)}'
    assert type(data['corrupt_frame']) is int, 'corrupt_frame must be an integer'
    assert type(data['corrupt_module']) is str, 'corrupt_module must be a string'
    assert type(data['impacted_deps']) is list, 'impacted_deps must be an array'
    assert all(type(item) is str for item in data['impacted_deps']), 'Dependency names must be strings'
    assert type(data['ascii_sum']) is int, 'ascii_sum must be an integer'

    assert data['corrupt_frame'] == expected['corrupt_frame'], (
        f"Expected corrupt_frame {expected['corrupt_frame']}, got {data['corrupt_frame']}"
    )
    assert data['corrupt_module'] == expected['corrupt_module'], (
        f"Expected corrupt_module {expected['corrupt_module']!r}, got {data['corrupt_module']!r}"
    )
    assert data['impacted_deps'] == expected['impacted_deps'], (
        f"Expected impacted_deps {expected['impacted_deps']}, got {data['impacted_deps']}"
    )
    assert data['ascii_sum'] == expected['ascii_sum'], (
        f"Expected ascii_sum {expected['ascii_sum']}, got {data['ascii_sum']}"
    )


def test_bash_workflow_exists_and_runs():
    assert SCRIPT.exists(), '/home/user/organize.sh does not exist'
    mode = SCRIPT.lstat().st_mode
    assert stat.S_ISREG(mode) and not SCRIPT.is_symlink(), 'organize.sh must be a regular file'

    source = SCRIPT.read_text(errors='replace')
    first_line = source.splitlines()[0] if source.splitlines() else ''
    assert re.match(r'^#!.*\bbash\b', first_line), 'organize.sh must be a Bash script'
    assert subprocess.run(['bash', '-n', str(SCRIPT)]).returncode == 0, 'organize.sh has invalid Bash syntax'

    active_source = '\n'.join(
        line for line in source.splitlines() if not line.lstrip().startswith('#')
    )
    assert 'deps.txt' in active_source, 'organize.sh does not read the dependency graph'
    assert re.search(r'\b(for|while|until)\b', active_source), (
        'organize.sh does not contain Bash graph-traversal control flow'
    )
    assert re.search(r'\bsort\b', active_source), 'organize.sh does not sort its dependency result'

    workflow_text = active_source.lower()
    for root in (Path('/home/user'), Path('/app')):
        for candidate in root.rglob('*'):
            if candidate != SCRIPT and candidate.is_file() and candidate.suffix in {'.sh', '.py'}:
                try:
                    workflow_text += '\n' + candidate.read_text(errors='replace').lower()
                except OSError:
                    pass
    assert 'ffmpeg' in workflow_text, 'No ffmpeg video-extraction step was found in the workflow'
    assert 'tesseract' in workflow_text, 'No tesseract OCR step was found in the workflow'

    try:
        result = subprocess.run(
            ['bash', str(SCRIPT)],
            cwd='/home/user',
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=15,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError('organize.sh did not finish while leaving the server in the background') from error
    assert result.returncode == 0, f'organize.sh exited with status {result.returncode}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
