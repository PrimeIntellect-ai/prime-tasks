#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

VIDEO = "/app/audit_video.mp4"
FRAMES = Path("/home/user/frames")
HASHER = Path("/home/user/hasher")
SOURCE = Path("/home/user/hasher.cpp")
SCRIPT = Path("/home/user/generate_trail.sh")
TRAIL = Path("/home/user/audit_trail.txt")
BASELINE = Path("/home/user/baseline.py")


def expected_hash(directory):
    current = hashlib.sha256(b"init").digest()
    for path in sorted(Path(directory).iterdir(), key=lambda p: p.name):
        if path.name.endswith(".jpg") and path.is_file():
            current = hashlib.sha256(current + path.read_bytes()).digest()
    return current.hex()


def run_hasher(directory, output):
    subprocess.run(
        [str(HASHER), str(directory), str(output)],
        check=True,
        timeout=30,
    )
    return Path(output).read_text().strip()


def test_frames_extracted_from_video():
    """Verify that the submitted frames are the requested ffmpeg extraction."""
    assert FRAMES.is_dir(), "Frames directory /home/user/frames does not exist."
    jpg_files = [p for p in FRAMES.iterdir() if p.name.endswith(".jpg")]
    assert jpg_files, "No .jpg files found in /home/user/frames."

    with tempfile.TemporaryDirectory(prefix="expected_frames_") as td:
        pattern = os.path.join(td, "frame_%04d.jpg")
        subprocess.run(
            ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
             "-i", VIDEO, "-vf", "fps=1", pattern],
            check=True,
            timeout=120,
        )
        expected = sorted(Path(td).glob("*.jpg"), key=lambda p: p.name)
        actual = sorted(jpg_files, key=lambda p: p.name)
        assert [p.name for p in actual] == [p.name for p in expected], \
            "Frame names/count do not match a 1 fps extraction of audit_video.mp4."
        for got, want in zip(actual, expected):
            assert hashlib.sha256(got.read_bytes()).digest() == hashlib.sha256(want.read_bytes()).digest(), \
                f"{got.name} was not extracted from audit_video.mp4 with the requested ffmpeg operation."


def test_hasher_artifacts_and_behavior():
    """Execute the binary on verifier-generated data and verify the hash chain."""
    assert SOURCE.is_file(), "C++ source /home/user/hasher.cpp is missing."
    assert HASHER.is_file(), "Compiled C++ hasher /home/user/hasher is missing."
    assert os.access(HASHER, os.X_OK), "Compiled C++ hasher is not executable."
    assert HASHER.read_bytes()[:4] == b"\x7fELF", "Hasher must be a compiled ELF executable."

    with tempfile.TemporaryDirectory(prefix="hasher_input_") as td:
        root = Path(td)
        names = ["frame_0010.jpg", "frame_0002.jpg", "frame_0001.jpg",
                 "z.jpg", "A.jpg", "empty.jpg"]
        for i, name in enumerate(names):
            data = os.urandom(8192 + i * 137)
            if name == "empty.jpg":
                data = b""
            (root / name).write_bytes(data)
        (root / "ignored.png").write_bytes(os.urandom(1000))
        (root / "also_ignored.JPG").write_bytes(os.urandom(1000))
        out = root / "result.txt"
        assert run_hasher(root, out) == expected_hash(root), \
            "Hasher did not implement the required alphabetical cumulative SHA-256 chain."

    with tempfile.TemporaryDirectory(prefix="empty_input_") as td:
        out = Path(td) / "result.txt"
        assert run_hasher(td, out) == hashlib.sha256(b"init").hexdigest(), \
            "Hasher produced the wrong result for an empty frame directory."


def test_generate_trail_script_and_sandbox():
    """Execute the script, then probe that its bwrap restrictions are effective."""
    assert SCRIPT.is_file(), f"Script {SCRIPT} is missing."
    content = SCRIPT.read_text()
    assert "bwrap" in content, "bwrap command not found in generate_trail.sh"
    assert "--unshare-net" in content, "--unshare-net constraint not found in generate_trail.sh"

    # Execute the real submitted binary through the submitted sandbox.
    subprocess.run(["bash", str(SCRIPT)], check=True, timeout=60)
    assert TRAIL.is_file(), f"Agent output file {TRAIL} is missing."
    assert TRAIL.read_text().strip() == expected_hash(FRAMES), \
        "generate_trail.sh did not produce the correct hash from the extracted frames."

    probe_source = r'''
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <ifaddrs.h>
#include <net/if.h>

static int readable(const char *p) {
    FILE *f = fopen(p, "rb");
    if (!f) return 0;
    fclose(f);
    return 1;
}
static int writable(const char *p) {
    FILE *f = fopen(p, "wb");
    if (!f) return 0;
    fclose(f);
    return 1;
}
int main(int argc, char **argv) {
    if (argc < 3) return 20;
    if (strcmp(argv[1], "/home/user/frames") != 0) return 21;
    if (strcmp(argv[2], "/home/user/audit_trail.txt") != 0) return 22;
    if (!readable("/home/user/frames/frame_0001.jpg")) return 23;
    if (readable("/home/user/sandbox_secret")) return 24;
    if (readable("/home/user/baseline.py")) return 25;
    if (readable("/etc/passwd")) return 26;
    if (writable("/tmp/sandbox_probe_escape")) return 27;
    if (writable("/home/user/forbidden_output")) return 28;

    struct ifaddrs *list = NULL, *it;
    if (getifaddrs(&list) == 0) {
        for (it = list; it; it = it->ifa_next) {
            if (it->ifa_name && !(it->ifa_flags & IFF_LOOPBACK)) {
                freeifaddrs(list);
                return 29;
            }
        }
        freeifaddrs(list);
    }

    FILE *out = fopen(argv[2], "wb");
    if (!out) return 30;
    fputs("SANDBOX_PROBE_OK\n", out);
    fclose(out);
    return 0;
}
'''
    probe_cpp = Path("/tmp/sandbox_probe.cpp")
    probe_bin = Path("/tmp/sandbox_probe")
    probe_cpp.write_text(probe_source)
    subprocess.run(["g++", "-O2", str(probe_cpp), "-o", str(probe_bin)], check=True)

    backup = Path("/tmp/original_agent_hasher")
    secret = Path("/home/user/sandbox_secret")
    forbidden = Path("/home/user/forbidden_output")
    backup.unlink(missing_ok=True)
    secret.write_text("must not be visible inside sandbox")
    forbidden.unlink(missing_ok=True)
    os.replace(HASHER, backup)
    try:
        shutil.copy2(probe_bin, HASHER)
        HASHER.chmod(0o755)
        subprocess.run(["bash", str(SCRIPT)], check=True, timeout=30)
        assert TRAIL.read_text().strip() == "SANDBOX_PROBE_OK", \
            "generate_trail.sh did not execute /home/user/hasher under the required restrictions."
        assert not forbidden.exists(), "Sandbox allowed writing an unauthorized user file."
    finally:
        HASHER.unlink(missing_ok=True)
        os.replace(backup, HASHER)
        secret.unlink(missing_ok=True)
        forbidden.unlink(missing_ok=True)
        Path("/tmp/sandbox_probe_escape").unlink(missing_ok=True)

    # Restore the required final artifact using the real binary.
    subprocess.run(["bash", str(SCRIPT)], check=True, timeout=60)
    assert TRAIL.read_text().strip() == expected_hash(FRAMES)


def test_audit_trail_hash_and_supplied_baseline():
    """Retain the original baseline comparison and independently derive the answer."""
    assert TRAIL.is_file(), f"Agent output file {TRAIL} is missing."
    independent = expected_hash(FRAMES)
    assert TRAIL.read_text().strip() == independent

    baseline_out = Path("/tmp/baseline_out.txt")
    subprocess.run(["python3", str(BASELINE), str(FRAMES), str(baseline_out)], check=True)
    assert baseline_out.read_text().strip() == independent, \
        "Supplied baseline was modified or produced an incorrect result."


def test_performance_speedup_with_verified_output():
    """Time both implementations while also verifying the timed hasher output."""
    assert HASHER.is_file() and os.access(HASHER, os.X_OK)

    trusted = Path("/tmp/trusted_baseline.py")
    trusted.write_text('''import hashlib, os, sys\nd, out = sys.argv[1], sys.argv[2]\nh = hashlib.sha256(b"init").digest()\nfor f in sorted(x for x in os.listdir(d) if x.endswith(".jpg")):\n    with open(os.path.join(d, f), "rb") as fp: data = fp.read()\n    h = hashlib.sha256(h + data).digest()\nwith open(out, "w") as fp: fp.write(h.hex() + "\\n")\n''')
    expected = expected_hash(FRAMES)
    py_out = Path("/tmp/perf_python.txt")
    cpp_out = Path("/tmp/perf_cpp.txt")

    subprocess.run(["python3", str(trusted), str(FRAMES), str(py_out)], check=True)
    subprocess.run([str(HASHER), str(FRAMES), str(cpp_out)], check=True)
    assert cpp_out.read_text().strip() == expected

    t0 = time.perf_counter()
    subprocess.run(["python3", str(trusted), str(FRAMES), str(py_out)], check=True)
    baseline_time = time.perf_counter() - t0

    t0 = time.perf_counter()
    subprocess.run([str(HASHER), str(FRAMES), str(cpp_out)], check=True)
    agent_time = max(time.perf_counter() - t0, 1e-9)
    assert py_out.read_text().strip() == expected
    assert cpp_out.read_text().strip() == expected, "Timed hasher invocation did not hash its input."
    speedup = baseline_time / agent_time
    assert speedup >= 2.0, \
        f"Speedup is {speedup:.2f}x, below 2.0x (Python {baseline_time:.4f}s, C++ {agent_time:.4f}s)."

    # Preserve the original performance assertion against the supplied baseline.
    subprocess.run(["python3", str(BASELINE), str(FRAMES), "/dev/null"], check=True)
    subprocess.run([str(HASHER), str(FRAMES), "/dev/null"], check=True)
    t0 = time.time()
    subprocess.run(["python3", str(BASELINE), str(FRAMES), "/dev/null"], check=True)
    original_baseline_time = time.time() - t0
    t0 = time.time()
    subprocess.run([str(HASHER), str(FRAMES), "/dev/null"], check=True)
    original_agent_time = max(time.time() - t0, 1e-9)
    original_speedup = original_baseline_time / original_agent_time
    assert original_speedup >= 2.0, \
        f"Original speedup check is only {original_speedup:.2f}x."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
