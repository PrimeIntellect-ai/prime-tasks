#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import math
import os
import random
import re
import signal
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = "http://127.0.0.1:8080"
ORIGINAL_BARCODE = "ACGTAACCGGTT"
ORIGINAL_CONSENSUS = "ACGTAACCGGTTATGCATGC"
READS_PATH = Path("/app/reads.txt")
VIDEO_PATH = Path("/app/calibration.mp4")


def get(path, timeout=5):
    try:
        with urllib.request.urlopen(BASE_URL + path, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="strict").strip()
            assert response.status == 200, (
                f"Expected status code 200 for {path}, got {response.status}. Response: {body}"
            )
            return body
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise AssertionError(f"Failed to connect to {BASE_URL}{path}: {exc}")


def parse_rate(text):
    try:
        value = float(text)
    except ValueError:
        raise AssertionError(f"Expected a float for error_rate, got '{text}'")
    assert math.isfinite(value), f"error_rate must be finite, got {value}"
    return value


def assert_rate_is_posterior_estimate(value):
    # Two mismatches among 56 observed bases and a Uniform(0, 0.5) prior give
    # an effectively untruncated Beta(3,55) posterior, whose mean is 3/58.
    expected = 3.0 / 58.0
    tolerance = 0.020  # permits ordinary Monte Carlo variation from 5,000 iterations
    assert abs(value - expected) <= tolerance, (
        f"Expected an MCMC estimate near posterior mean {expected:.6f}, got {value}"
    )


def listening_pid(port):
    inodes = set()
    target = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == target and fields[3] == "0A":
                inodes.add(fields[9])
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", link)
                if match and match.group(1) in inodes:
                    return int(proc.name)
        except OSError:
            continue
    raise AssertionError(f"No process was found listening on port {port}")


def find_cpp_sources():
    found = []
    ignored = {".git", "node_modules", "site-packages", "dist-packages", "proc", "sys", "dev"}
    for root in ("/app", "/home", "/root", "/workspace", "/tmp"):
        if not os.path.isdir(root):
            continue
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in ignored]
            for name in files:
                if name.lower().endswith((".cpp", ".cc", ".cxx", ".hpp", ".hh", ".hxx")):
                    path = Path(base) / name
                    try:
                        if path.stat().st_size <= 2_000_000:
                            found.append(path)
                    except OSError:
                        pass
    return found


def check_cpp_implementation(pid):
    exe = Path(f"/proc/{pid}/exe").resolve()
    assert exe.is_file(), "The process serving port 8080 is not backed by an executable file"
    with exe.open("rb") as handle:
        assert handle.read(4) == b"\x7fELF", "The HTTP service must be the compiled native binary"

    sources = find_cpp_sources()
    assert sources, "No C++ source file implementing the requested workflow was found"
    chunks = []
    for source in sources:
        try:
            chunks.append(source.read_text(errors="ignore"))
        except OSError:
            pass
    code = "\n".join(chunks)
    low = code.lower()

    assert "calibration.mp4" in low and "ffmpeg" in low, (
        "C++ source must process calibration.mp4 with ffmpeg or equivalent video extraction logic"
    )
    assert "reads.txt" in low, "C++ source must read /app/reads.txt"
    assert any(term in low for term in ("debruijn", "de bruijn", "kmer", "k-mer")), (
        "C++ source does not contain De Bruijn/k-mer assembly logic"
    )
    assert any(term in low for term in ("adjacency", "graph", "euler")) and "stack" in low, (
        "C++ source does not contain graph traversal/Eulerian assembly logic"
    )
    assert any(term in low for term in ("metropolis", "acceptance", "accept_ratio", "acceptance_ratio")), (
        "C++ source does not contain Metropolis-Hastings acceptance logic"
    )
    assert any(term in low for term in ("mt19937", "uniform_real_distribution", "random_device")), (
        "C++ source does not use a C++ random generator for MCMC"
    )
    iteration_constants = [int(x) for x in re.findall(r"\b\d{4,}\b", code)]
    assert any(x >= 5000 for x in iteration_constants), "MCMC source does not specify at least 5,000 iterations"
    assert "8080" in code and "bind" in low and "listen" in low and "accept" in low, (
        "C++ source does not contain the required socket HTTP server"
    )
    return exe


def process_metadata(pid):
    exe = Path(f"/proc/{pid}/exe").resolve()
    raw_args = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    args = [x.decode(errors="surrogateescape") for x in raw_args if x]
    assert args, "Could not determine server command line"
    args[0] = str(exe)
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="ignore")] = value.decode(errors="surrogateescape")
    except OSError:
        pass
    return args, cwd, env


def stop_listener(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 5
    while time.time() < deadline:
        if not Path(f"/proc/{pid}").exists():
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def make_video(barcode, output):
    colors = {
        "A": bytes((255, 0, 0)),
        "C": bytes((0, 255, 0)),
        "G": bytes((0, 0, 255)),
        "T": bytes((255, 255, 0)),
    }
    raw = Path("/tmp/verifier_frames.rgb")
    with raw.open("wb") as handle:
        for base in barcode:
            handle.write(colors[base] * (32 * 32))
    subprocess.run([
        "ffmpeg", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", "32x32",
        "-framerate", "1", "-i", str(raw), "-frames:v", "12",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "1", str(output)
    ], check=True, timeout=30)


def wait_for_server(timeout=15):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            get("/barcode", timeout=1)
            return
        except Exception as exc:
            last = exc
            time.sleep(0.25)
    raise AssertionError(f"Restarted C++ server did not bind to port 8080: {last}")


# Preserve the original endpoint assertions, correcting only the mathematically
# inconsistent error-rate interval.
assert get("/barcode") == ORIGINAL_BARCODE, (
    f"Expected barcode '{ORIGINAL_BARCODE}'"
)
assert get("/consensus") == ORIGINAL_CONSENSUS, (
    f"Expected consensus '{ORIGINAL_CONSENSUS}'"
)
assert_rate_is_posterior_estimate(parse_rate(get("/error_rate")))

pid = listening_pid(8080)
check_cpp_implementation(pid)
args, cwd, env = process_metadata(pid)

original_reads = READS_PATH.read_bytes()
original_video = VIDEO_PATH.read_bytes()
spawned = None
try:
    # Apply a verifier-selected nucleotide permutation to both raw artifacts.
    # This preserves graph topology, alignments, mismatch count, and task
    # difficulty while making fixed endpoint constants insufficient.
    bases = list("ACGT")
    rng = random.SystemRandom()
    while True:
        shuffled = rng.sample(bases, len(bases))
        mapping = dict(zip(bases, shuffled))
        if any(mapping[x] != x for x in bases):
            break

    def transform(text):
        return "".join(mapping.get(ch, ch) for ch in text)

    variant_barcode = transform(ORIGINAL_BARCODE)
    variant_consensus = transform(ORIGINAL_CONSENSUS)
    variant_reads = transform(original_reads.decode("ascii"))

    READS_PATH.write_text(variant_reads)
    make_video(variant_barcode, VIDEO_PATH)

    stop_listener(pid)
    spawned = subprocess.Popen(
        args, cwd=cwd, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_server()

    actual_barcode = get("/barcode")
    actual_consensus = get("/consensus")
    assert actual_barcode == variant_barcode, (
        f"Server did not extract the verifier-generated video barcode: expected {variant_barcode}, got {actual_barcode}"
    )
    assert actual_consensus == variant_consensus, (
        f"Server did not assemble the verifier-transformed reads: expected {variant_consensus}, got {actual_consensus}"
    )
    assert_rate_is_posterior_estimate(parse_rate(get("/error_rate")))
finally:
    READS_PATH.write_bytes(original_reads)
    VIDEO_PATH.write_bytes(original_video)
    try:
        current = listening_pid(8080)
        stop_listener(current)
    except Exception:
        if spawned is not None and spawned.poll() is None:
            spawned.kill()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
