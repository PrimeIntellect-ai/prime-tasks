#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import subprocess
import json
import urllib.request
import urllib.error
import pytest

def get_expected_sizes():
    try:
        out = subprocess.check_output(
            ['ffprobe', '-show_frames', '-select_streams', 'v:0', '-of', 'json', '/app/video.mp4'],
            stderr=subprocess.DEVNULL
        )
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run ffprobe on /app/video.mp4")

    data = json.loads(out)
    frames = sorted(data['frames'], key=lambda x: int(x['coded_picture_number']))

    nodes = {}
    for f in frames:
        idx = int(f['coded_picture_number'])
        nodes[idx] = {
            'type': f['pict_type'],
            'size': int(f['pkt_size']),
            'deps': []
        }

    frame_ids = sorted(nodes)
    for pos, idx in enumerate(frame_ids):
        if nodes[idx]['type'] == 'P':
            for prev_idx in reversed(frame_ids[:pos]):
                if nodes[prev_idx]['type'] in ('I', 'P'):
                    nodes[idx]['deps'].append(prev_idx)
                    break
        elif nodes[idx]['type'] == 'B':
            for prev_idx in reversed(frame_ids[:pos]):
                if nodes[prev_idx]['type'] in ('I', 'P'):
                    nodes[idx]['deps'].append(prev_idx)
                    break
            for next_idx in frame_ids[pos + 1:]:
                if nodes[next_idx]['type'] in ('I', 'P'):
                    nodes[idx]['deps'].append(next_idx)
                    break

    def get_all_deps(idx, visited):
        if idx in visited:
            return
        visited.add(idx)
        for dep in nodes[idx]['deps']:
            get_all_deps(dep, visited)

    expected_sizes = {}
    for idx in frame_ids:
        visited = set()
        get_all_deps(idx, visited)
        expected_sizes[idx] = sum(nodes[v]['size'] for v in visited)

    return expected_sizes

@pytest.fixture(scope="module")
def expected_sizes():
    return get_expected_sizes()

def query_dependency_size(test_frame):
    url = f'http://127.0.0.1:8080/dependency_size?frame={test_frame}'
    try:
        req = urllib.request.urlopen(url, timeout=5)
        assert req.status == 200, f"Expected HTTP 200 for frame {test_frame}, got {req.status}"
        res = req.read().decode('utf-8').strip()
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to or read from {url}: {e}")

    try:
        return int(res)
    except ValueError:
        pytest.fail(f"Expected an integer response, got: '{res}'")

@pytest.mark.parametrize("test_frame", [0, 2, 5, 10, 15, 19])
def test_dependency_size(expected_sizes, test_frame):
    if test_frame not in expected_sizes:
        pytest.skip(f"Frame {test_frame} not found in video")

    actual_size = query_dependency_size(test_frame)
    expected_size = expected_sizes[test_frame]
    assert actual_size == expected_size, f"Frame {test_frame}: expected size {expected_size}, got {actual_size}"

def test_dependency_size_for_every_frame(expected_sizes):
    assert expected_sizes, "No video frames found"
    for test_frame, expected_size in sorted(expected_sizes.items()):
        actual_size = query_dependency_size(test_frame)
        assert actual_size == expected_size, f"Frame {test_frame}: expected size {expected_size}, got {actual_size}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
