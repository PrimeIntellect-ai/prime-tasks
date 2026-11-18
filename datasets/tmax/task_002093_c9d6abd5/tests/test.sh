#!/bin/bash
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

mkdir -p /app /home/user/vid-parser/lib || fail
[ -f /home/user/vid-parser/processor.go ] || fail
[ -f /home/user/vid-parser/lib/vidproc.h ] || fail

# Recreate a functional, randomized video/library pair so deleted or originally
# empty fixtures cannot turn the verification into a skip or an empty oracle.
python3 - <<'PY' || exit 20
import json
import os
import random
import secrets
import subprocess

versions = [
    "1.0.0-alpha",
    "1.0.0-alpha.1",
    "1.0.0-alpha.beta",
    "1.0.0-beta",
    "1.0.0-beta.2",
    "1.0.0-beta.11",
    "1.0.0-rc.1",
    "1.0.0",
    "1.0.0+build.x",
    f"0.{secrets.randbelow(40) + 10}.{secrets.randbelow(40) + 10}",
    f"2.{secrets.randbelow(40) + 10}.{secrets.randbelow(40) + 10}-preview.3",
    f"3.{secrets.randbelow(40) + 10}.{secrets.randbelow(40) + 10}",
]
random.SystemRandom().shuffle(versions)
levels = [10 + 20 * i for i in range(len(versions))]

entries = ",\n".join(json.dumps(v) for v in versions)
level_entries = ", ".join(str(x) for x in levels)
source = f'''#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#pragma pack(push, 1)
typedef struct {{
    uint32_t frame_id;
    uint8_t semver_len;
    char semver_str[32];
    uint16_t checksum;
}} MetadataPayload;
#pragma pack(pop)
static const char *versions[] = {{
{entries}
}};
static const unsigned char levels[] = {{ {level_entries} }};
MetadataPayload* process_frame(const unsigned char* frame_data, int width, int height) {{
    if (!frame_data || width <= 0 || height <= 0) return NULL;
    int best = 0;
    int best_dist = 1000;
    for (int i = 0; i < {len(versions)}; ++i) {{
        int d = (int)frame_data[0] - (int)levels[i];
        if (d < 0) d = -d;
        if (d < best_dist) {{ best_dist = d; best = i; }}
    }}
    MetadataPayload *p = (MetadataPayload*)calloc(1, sizeof(MetadataPayload));
    if (!p) return NULL;
    p->frame_id = (uint32_t)best;
    size_t n = strlen(versions[best]);
    if (n > 32) n = 32;
    p->semver_len = (uint8_t)n;
    memcpy(p->semver_str, versions[best], n);
    uint16_t sum = 0;
    for (size_t i = 0; i < n; ++i) sum = (uint16_t)(sum + (unsigned char)versions[best][i]);
    p->checksum = sum;
    return p;
}}
void free_payload(MetadataPayload* payload) {{ free(payload); }}
'''
with open('/tmp/vidproc_fixture.c', 'w') as f:
    f.write(source)
os.chmod('/tmp/vidproc_fixture.c', 0o600)

subprocess.run([
    'gcc', '-shared', '-fPIC', '-O2', '-o',
    '/home/user/vid-parser/lib/libvidproc.so', '/tmp/vidproc_fixture.c'
], check=True)
os.chmod('/home/user/vid-parser/lib/libvidproc.so', 0o755)

width = height = 16
with open('/tmp/test_sequence.rgb', 'wb') as f:
    for level in levels:
        f.write(bytes([level, level, level]) * width * height)

subprocess.run([
    'ffmpeg', '-y', '-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
    '-s', f'{width}x{height}', '-r', '1', '-i', '/tmp/test_sequence.rgb',
    '-an', '-c:v', 'libx264rgb', '-qp', '0', '-preset', 'ultrafast',
    '/app/test_sequence.mp4'
], check=True)
os.chmod('/app/test_sequence.mp4', 0o644)
os.remove('/tmp/test_sequence.rgb')
os.remove('/tmp/vidproc_fixture.c')
PY
[ $? -eq 0 ] || fail

# Derive the expected result from the actual randomized video and C ABI before
# executing untrusted submitted code.
python3 - <<'PY' || exit 21
import ctypes
import json
import os
import re
import subprocess

class MetadataPayload(ctypes.Structure):
    _pack_ = 1
    _fields_ = [
        ('frame_id', ctypes.c_uint32),
        ('semver_len', ctypes.c_uint8),
        ('semver_str', ctypes.c_char * 32),
        ('checksum', ctypes.c_uint16),
    ]

def parse_semver(v):
    m = re.match(r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$', v)
    if not m:
        return (0, 0, 0, [(2,)])
    major, minor, patch, prerelease, build = m.groups()
    if prerelease:
        parts = []
        for p in prerelease.split('.'):
            parts.append((0, int(p)) if p.isdigit() else (1, p))
    else:
        parts = [(2,)]
    return (int(major), int(minor), int(patch), parts)

video = '/app/test_sequence.mp4'
lib_path = '/home/user/vid-parser/lib/libvidproc.so'
if not os.path.isfile(video) or not os.path.isfile(lib_path):
    raise SystemExit('required fixture missing')

dims = subprocess.check_output([
    'ffprobe', '-v', 'error', '-select_streams', 'v:0',
    '-show_entries', 'stream=width,height', '-of', 'csv=s=x:p=0', video
], text=True).strip()
width, height = map(int, dims.split('x'))
raw = subprocess.check_output([
    'ffmpeg', '-v', 'error', '-i', video, '-f', 'image2pipe',
    '-pix_fmt', 'rgb24', '-vcodec', 'rawvideo', '-'
])
frame_size = width * height * 3
if frame_size <= 0 or len(raw) < frame_size or len(raw) % frame_size != 0:
    raise SystemExit('video did not decode into complete frames')

lib = ctypes.CDLL(lib_path)
lib.process_frame.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
lib.process_frame.restype = ctypes.POINTER(MetadataPayload)
lib.free_payload.argtypes = [ctypes.POINTER(MetadataPayload)]
lib.free_payload.restype = None
versions = []
for offset in range(0, len(raw), frame_size):
    frame = ctypes.create_string_buffer(raw[offset:offset + frame_size])
    ptr = lib.process_frame(frame, width, height)
    if ptr:
        payload = ptr.contents
        versions.append(bytes(payload.semver_str[:payload.semver_len]).decode('utf-8'))
        lib.free_payload(ptr)
if not versions:
    raise SystemExit('library returned no metadata')
versions.sort(key=parse_semver)
with open('/tmp/expected_sorted_versions.json', 'w') as f:
    json.dump(versions, f)
os.chmod('/tmp/expected_sorted_versions.json', 0o600)
PY
[ $? -eq 0 ] || fail

rm -f /home/user/sorted_versions.json

# Build and execute the submitted Go package with no verifier-supplied library
# search path. A correct submission must provide its own compile/runtime linking.
runuser -u user -- env -u LD_LIBRARY_PATH HOME=/home/user \
    timeout 120s sh -c 'cd /home/user/vid-parser && GO111MODULE=off go run .' \
    >/tmp/submission.log 2>&1 || fail

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
from difflib import SequenceMatcher


def parse_semver(v):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$", v)
    if not m:
        return (0, 0, 0, [(2,)])
    major, minor, patch, prerelease, build = m.groups()
    major, minor, patch = int(major), int(minor), int(patch)
    if prerelease:
        pre_parts = []
        for p in prerelease.split('.'):
            if p.isdigit():
                pre_parts.append((0, int(p)))
            else:
                pre_parts.append((1, p))
    else:
        pre_parts = [(2,)]
    return (major, minor, patch, pre_parts)


def get_ground_truth():
    with open('/tmp/expected_sorted_versions.json', 'r') as f:
        return json.load(f)


def test_sorted_versions_accuracy():
    output_file = '/home/user/sorted_versions.json'
    assert os.path.isfile(output_file), f'Output file {output_file} does not exist.'
    with open(output_file, 'r') as f:
        agent_output = json.load(f)
    assert isinstance(agent_output, list), 'Output JSON must be a list of strings.'
    assert all(isinstance(v, str) for v in agent_output), 'Output JSON must be a list of strings.'

    ground_truth = get_ground_truth()
    assert ground_truth, 'Ground truth must contain processed video metadata.'
    matcher = SequenceMatcher(None, ground_truth, agent_output)
    accuracy = matcher.ratio()
    assert accuracy >= 0.95, f'SequenceMatcher accuracy {accuracy:.4f} is below threshold 0.95'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
