#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_process_script_exists_and_executable():
    path = "/home/user/process.sh"
    assert os.path.exists(path), f"Bash script {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"Bash script {path} is not executable."

def test_c_source_exists():
    path = "/home/user/distance.c"
    assert os.path.exists(path), f"C source file {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."

def test_c_binary_exists_and_executable():
    path = "/home/user/distance_calc"
    assert os.path.exists(path), f"Compiled C binary {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"Compiled C binary {path} is not executable."

def test_valid_distances_output():
    path = "/home/user/valid_distances.txt"
    assert os.path.exists(path), f"Final output file {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1620000000 0.00",
        "1620000002 5.00",
        "1620000007 5.00"
    ]

    assert lines == expected_lines, f"Contents of {path} do not match the expected output. Got: {lines}, Expected: {expected_lines}"
TEST_EOF

cleanup() {
    if [ -d /tmp/verifier_backup ]; then
        cp -f /tmp/verifier_backup/sensor1.txt /home/user/sensor1.txt 2>/dev/null || true
        cp -f /tmp/verifier_backup/sensor2.txt /home/user/sensor2.txt 2>/dev/null || true
        cp -f /tmp/verifier_backup/distance.c /home/user/distance.c 2>/dev/null || true
        cp -f /tmp/verifier_backup/distance_calc /home/user/distance_calc 2>/dev/null || true
        cp -f /tmp/verifier_backup/valid_distances.txt /home/user/valid_distances.txt 2>/dev/null || true
    fi
}
trap cleanup EXIT

run_tests() {
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    rm -rf /tmp/verifier_backup
    mkdir -p /tmp/verifier_backup
    cp /home/user/sensor1.txt /tmp/verifier_backup/sensor1.txt || return 1
    cp /home/user/sensor2.txt /tmp/verifier_backup/sensor2.txt || return 1
    cp /home/user/distance.c /tmp/verifier_backup/distance.c || return 1
    cp /home/user/distance_calc /tmp/verifier_backup/distance_calc || return 1
    cp /home/user/valid_distances.txt /tmp/verifier_backup/valid_distances.txt || return 1

    gcc /home/user/distance.c -o /tmp/recompiled_distance_calc -lm || return 1

    python3 - << 'PY' || return 1
import subprocess

sample = b'''42 0 0 0 3 4 0
43 1 2 3 7 10 3
44 0 0 0 9 12 0
45 -1 -1 -1 0 0 0
'''
expected = "42 5.00\n43 10.00\n45 1.73\n"
for executable in ("/home/user/distance_calc", "/tmp/recompiled_distance_calc"):
    result = subprocess.run(
        [executable], input=sample, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5, check=True
    )
    actual = result.stdout.decode()
    assert actual == expected, (
        f"{executable} failed distance computation or validation: "
        f"got {actual!r}, expected {expected!r}"
    )
PY

    # Install a behaviorally equivalent instrumented calculator temporarily. It
    # records invocation sizes and overlap, while still forcing process.sh to do
    # the sorting, joining, chunking, parallel orchestration, and final sorting.
    cat << 'C_EOF' > /home/user/distance.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/types.h>
#include <sys/stat.h>

static void read_state(int fd, int *calls, int *active, int *maximum) {
    char buf[128] = {0};
    lseek(fd, 0, SEEK_SET);
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n <= 0 || sscanf(buf, "%d %d %d", calls, active, maximum) != 3)
        *calls = *active = *maximum = 0;
}

static void write_state(int fd, int calls, int active, int maximum) {
    ftruncate(fd, 0);
    lseek(fd, 0, SEEK_SET);
    dprintf(fd, "%d %d %d\n", calls, active, maximum);
    fsync(fd);
}

int main(void) {
    int fd = open("/tmp/distance_invocation_state", O_RDWR | O_CREAT, 0666);
    if (fd < 0) return 90;
    flock(fd, LOCK_EX);
    int calls, active, maximum;
    read_state(fd, &calls, &active, &maximum);
    calls++;
    active++;
    if (active > maximum) maximum = active;
    write_state(fd, calls, active, maximum);
    flock(fd, LOCK_UN);

    usleep(250000);

    long long timestamp;
    double x1, y1, z1, x2, y2, z2;
    int line_count = 0;
    while (scanf("%lld %lf %lf %lf %lf %lf %lf",
                 &timestamp, &x1, &y1, &z1, &x2, &y2, &z2) == 7) {
        line_count++;
        double dx = x1 - x2, dy = y1 - y2, dz = z1 - z2;
        double distance = sqrt(dx * dx + dy * dy + dz * dz);
        if (distance <= 10.0)
            printf("%lld %.2f\n", timestamp, distance);
    }

    flock(fd, LOCK_EX);
    int chunk_fd = open("/tmp/distance_chunk_sizes", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (chunk_fd >= 0) {
        dprintf(chunk_fd, "%d\n", line_count);
        close(chunk_fd);
    }
    read_state(fd, &calls, &active, &maximum);
    active--;
    write_state(fd, calls, active, maximum);
    flock(fd, LOCK_UN);
    close(fd);
    return 0;
}
C_EOF
    gcc /home/user/distance.c -o /home/user/distance_calc -lm || return 1
    chmod +x /home/user/distance_calc || return 1

    python3 - << 'PY' || return 1
import os
import random

base = 1750000000 + int.from_bytes(os.urandom(2), "big") * 300
sensor1 = []
sensor2 = []
expected = []
patterns = [
    ((0, 0, 0), "0.00"),
    ((3, 4, 0), "5.00"),
    ((6, 8, 0), "10.00"),
    ((9, 12, 0), None),
]
for i in range(235):
    timestamp = base + i
    x, y, z = (i % 17) - 8, (i % 13) - 6, (i % 11) - 5
    (dx, dy, dz), formatted = patterns[i % len(patterns)]
    sensor1.append(f"{timestamp} {x} {y} {z}\n")
    sensor2.append(f"{timestamp} {x + dx} {y + dy} {z + dz}\n")
    if formatted is not None:
        expected.append(f"{timestamp} {formatted}")

# Records present in only one sensor must be discarded by the exact join.
sensor1.extend([
    f"{base - 11} 1 2 3\n",
    f"{base + 500} 4 5 6\n",
])
sensor2.extend([
    f"{base - 9} 1 2 3\n",
    f"{base + 501} 4 5 6\n",
])
random.SystemRandom().shuffle(sensor1)
random.SystemRandom().shuffle(sensor2)
with open("/home/user/sensor1.txt", "w") as f:
    f.writelines(sensor1)
with open("/home/user/sensor2.txt", "w") as f:
    f.writelines(sensor2)
with open("/tmp/expected_dynamic_output", "w") as f:
    f.write("\n".join(expected) + "\n")
PY

    rm -f /tmp/distance_invocation_state /tmp/distance_chunk_sizes
    (cd /home/user && timeout 30 /home/user/process.sh) || return 1

    python3 - << 'PY' || return 1
from pathlib import Path

actual_path = Path("/home/user/valid_distances.txt")
assert actual_path.is_file(), "process.sh did not produce valid_distances.txt"
actual = actual_path.read_text()
expected = Path("/tmp/expected_dynamic_output").read_text()
assert actual == expected, (
    "process.sh failed on shuffled, mismatched, dynamically generated input; "
    f"got {actual!r}, expected {expected!r}"
)

state_path = Path("/tmp/distance_invocation_state")
chunks_path = Path("/tmp/distance_chunk_sizes")
assert state_path.is_file(), "process.sh did not invoke /home/user/distance_calc"
assert chunks_path.is_file(), "No calculator chunk invocations were recorded"
calls, active, maximum = map(int, state_path.read_text().split())
chunks = sorted(int(x) for x in chunks_path.read_text().split())
assert active == 0, "Calculator processes did not finish cleanly"
assert calls == 3 and chunks == [35, 100, 100], (
    f"Joined input was not split into 100-line chunks: calls={calls}, chunks={chunks}"
)
assert maximum >= 2, (
    f"Chunks were not processed in parallel; maximum concurrent calculators was {maximum}"
)
PY
}

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
