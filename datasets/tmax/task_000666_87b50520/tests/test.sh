#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import signal
import socket
import struct
import subprocess
import tempfile
import time
import urllib.request
import uuid
import zlib

import pytest

SRC = "/home/user/src"
BUILD = "/home/user/build"


def test_c_code_fixed_and_functional():
    path = os.path.join(SRC, "checksum.c")
    assert os.path.isfile(path), f"File {path} is missing."
    content = open(path).read()
    assert "i <= len" not in content, f"File {path} still contains the OOB read bug (i <= len)."
    assert "i < len" in content, f"File {path} does not appear to be fixed correctly."

    harness = r'''#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include "checksum.h"
int main(void) {
    long p = sysconf(_SC_PAGESIZE);
    uint8_t *m = mmap(NULL, (size_t)p * 2, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED || mprotect(m + p, p, PROT_NONE)) return 2;
    size_t sizes[] = {0, 1, 257, 4096};
    for (size_t c = 0; c < sizeof(sizes)/sizeof(sizes[0]); c++) {
        size_t n = sizes[c];
        uint8_t *d = m + p - n;
        for (size_t i = 0; i < n; i++) d[i] = (uint8_t)((i * 73 + 19) & 255);
        printf("%u\n", calculate_checksum(d, n));
    }
    return 0;
}'''
    with open("/tmp/checksum_harness.c", "w") as f:
        f.write(harness)
    subprocess.run([
        "gcc", "-std=c11", "-D_GNU_SOURCE", "-O2", "-Wall", "-Werror",
        "-I" + SRC, "/tmp/checksum_harness.c", path, "-o", "/tmp/checksum_harness"
    ], check=True, timeout=30)
    result = subprocess.run(["/tmp/checksum_harness"], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=10)
    assert result.returncode == 0, "checksum.c read outside the supplied buffer or crashed: " + result.stderr
    actual = [int(x) for x in result.stdout.splitlines()]
    expected = []
    for n in (0, 1, 257, 4096):
        data = bytes(((i * 73 + 19) & 255) for i in range(n))
        expected.append(zlib.adler32(data) & 0xffffffff)
    assert actual == expected, f"C checksum results are wrong: expected {expected}, got {actual}"


def _go_metadata(path):
    result = subprocess.run(["go", "version", "-m", path], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=20)
    assert result.returncode == 0, f"{path} is not a valid Go executable: {result.stderr}"
    return result.stdout


def _check_elf(path, machine, arch):
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", f"File {path} is not a valid ELF binary."
    assert header[18:20] == machine, f"File {path} is not a {arch} binary."
    assert os.path.getsize(path) > 100000, f"File {path} is implausibly small."
    elf = subprocess.run(["readelf", "-h", "-l", path], stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, timeout=20)
    assert elf.returncode == 0 and "Program Headers" in elf.stdout, f"Invalid executable ELF {path}: {elf.stderr}"
    metadata = _go_metadata(path)
    assert f"GOARCH={arch}" in metadata, f"{path} was not built for {arch}: {metadata}"
    assert "CGO_ENABLED=1" in metadata, f"{path} was not built with CGO enabled: {metadata}"


def test_server_arm64_binary():
    _check_elf(os.path.join(BUILD, "server_arm64"), b"\xb7\x00", "arm64")


def test_server_amd64_binary():
    _check_elf(os.path.join(BUILD, "server_amd64"), b"\x3e\x00", "amd64")


def test_benchmark_output_and_benchmark():
    path = "/home/user/bench.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    content = open(path).read()
    assert "Benchmark" in content or "ns/op" in content, f"File {path} does not contain valid Go benchmark output."
    assert re.search(r"(?m)^Benchmark\S+-\d+\s+\d+\s+.*ns/op", content), \
        "bench.txt does not contain a completed Go benchmark result."

    test_path = os.path.join(SRC, "checksum_test.go")
    assert os.path.isfile(test_path), f"File {test_path} is missing."
    test_source = open(test_path).read()
    assert re.search(r"func\s+Benchmark\w+\s*\(", test_source), "checksum_test.go has no Go benchmark function."
    compact = re.sub(r"\s+", "", test_source)
    assert any(x in compact for x in ("1024*1024", "1<<20", "1048576")), \
        "The benchmark does not create a 1MB dummy byte slice."
    assert re.search(r"checksum|calculate_checksum|C\.", test_source, re.I), \
        "The benchmark does not appear to call the checksum wrapper."

    run = subprocess.run(["go", "test", "-run", "^$", "-bench", ".", "-benchtime=1x"],
                         cwd=SRC, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, timeout=120, env={**os.environ, "CGO_ENABLED": "1"})
    assert run.returncode == 0, "The submitted benchmark cannot be run:\n" + run.stdout
    assert re.search(r"(?m)^Benchmark\S+-\d+\s+\d+\s+.*ns/op", run.stdout), \
        "Running go test did not execute a benchmark:\n" + run.stdout


def _post(path):
    body = json.dumps({"video_path": path}).encode()
    request = urllib.request.Request("http://127.0.0.1:8080/process", data=body,
                                     headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            status = response.status
            text = response.read().decode()
    except Exception as e:
        pytest.fail(f"Failed to connect to the HTTP service: {e}")
    assert status == 200, f"Expected status code 200, got {status}. Response: {text}"
    try:
        data = json.loads(text)
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {text}")
    assert "checksum" in data, f"Response JSON does not contain 'checksum' key: {data}"
    return data["checksum"]


def _expected(path):
    cmd = ["ffmpeg", "-i", path, "-vframes", "10", "-f", "image2pipe",
           "-vcodec", "rawvideo", "-pix_fmt", "rgb24", "-"]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert proc.returncode == 0, "Failed to run ffmpeg for expected checksum: " + proc.stderr.decode(errors="replace")
    return zlib.adler32(proc.stdout) & 0xffffffff


def _make_videos():
    directory = os.path.join("/tmp", "verifier_videos_" + uuid.uuid4().hex)
    os.mkdir(directory)
    specs = [("176x144", "13", "1.2"), ("128x96", "17", "0.9")]
    paths = []
    for i, (size, rate, duration) in enumerate(specs):
        path = os.path.join(directory, f"input_{i}_{uuid.uuid4().hex}.mp4")
        cmd = ["/usr/bin/ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-f", "lavfi",
               "-i", f"testsrc2=size={size}:rate={rate}:duration={duration}",
               "-c:v", "mpeg4", path]
        subprocess.run(cmd, check=True, timeout=60)
        paths.append(path)
    return paths


def _kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if int(fields[1].rsplit(":", 1)[1], 16) == 8080:
                inodes.add(fields[9])
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        if pid == os.getpid():
            continue
        try:
            for fd in os.listdir(procdir + "/fd"):
                try:
                    target = os.readlink(procdir + "/fd/" + fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(pid, signal.SIGTERM)
                    break
        except (OSError, ProcessLookupError):
            pass
    time.sleep(0.8)


def _wait_for_server(proc):
    deadline = time.time() + 15
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail("Server exited during startup: " + proc.stderr.read())
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.25):
                return
        except OSError:
            time.sleep(0.15)
    pytest.fail("Server did not listen on 127.0.0.1:8080")


def _exercise_started(binary, videos, require_wrapper):
    _kill_port_8080()
    wrapper_dir = tempfile.mkdtemp(prefix="ffmpeg_wrapper_")
    log = os.path.join(wrapper_dir, "calls.log")
    wrapper = os.path.join(wrapper_dir, "ffmpeg")
    with open(wrapper, "w") as f:
        f.write('#!/bin/sh\nprintf "%s\\n" "$*" >> "$VERIFY_FFMPEG_LOG"\nexec /usr/bin/ffmpeg "$@"\n')
    os.chmod(wrapper, 0o755)
    env = dict(os.environ)
    env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
    env["VERIFY_FFMPEG_LOG"] = log
    proc = subprocess.Popen([binary], cwd=SRC, env=env, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True)
    try:
        _wait_for_server(proc)
        for video in videos:
            assert _post(video) == _expected(video), f"Wrong checksum for generated input {video}"
        if require_wrapper:
            calls = open(log).read().splitlines() if os.path.exists(log) else []
            for video in videos:
                exact = f"-i {video} -vframes 10 -f image2pipe -vcodec rawvideo -pix_fmt rgb24 -"
                assert exact in calls, f"Service did not invoke ffmpeg with the required arguments for {video}. Calls: {calls}"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_http_service_process():
    # Preserve the original assertion that the agent left a service running.
    original_video = "/app/test_video.mp4"
    assert os.path.exists(original_video), "Test video file is missing."
    videos = _make_videos()
    for video in videos:
        assert _post(video) == _expected(video), f"The running service returned a wrong checksum for {video}"

    go_files = [p for p in glob.glob(os.path.join(SRC, "*.go")) if not p.endswith("_test.go")]
    assert os.path.isfile(os.path.join(SRC, "main.go")), "main.go is missing."
    source = "\n".join(open(p).read() for p in go_files)
    assert 'import "C"' in source or re.search(r'import\s*\([^)]*"C"', source, re.S), "The service does not use cgo."
    assert re.search(r"C\.calculate_checksum\s*\(", source), "The Go service does not call calculate_checksum through cgo."
    assert '"os/exec"' in source and re.search(r'exec\.Command\s*\(\s*"ffmpeg"', source), \
        "The service does not run ffmpeg through os/exec."
    for token in ('"-vframes"', '"10"', '"image2pipe"', '"rawvideo"', '"rgb24"'):
        assert token in source, f"The required ffmpeg argument {token} is missing from the service source."

    _kill_port_8080()
    verified = "/tmp/verified_source_server"
    build = subprocess.run(["go", "build", "-o", verified, "."], cwd=SRC,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                           timeout=120, env={**os.environ, "CGO_ENABLED": "1"})
    assert build.returncode == 0, "The submitted Go/C source does not build:\n" + build.stdout

    # Exercise both freshly built source and the submitted amd64 cross-compiled artifact.
    _exercise_started(verified, videos, True)
    _exercise_started(os.path.join(BUILD, "server_amd64"), videos, True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
