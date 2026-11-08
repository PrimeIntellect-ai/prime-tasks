#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import struct
import subprocess
import time
import wave

import numpy as np
import pytest
import requests

RAW = "/app/alert_raw.wav"
QUIET = "/home/user/alert_quiet.wav"
URL_8080 = "http://127.0.0.1:8080/alert_quiet.wav"
URL_9090 = "http://127.0.0.1:9090/alert_quiet.wav"


def halved_wav(raw):
    assert len(raw) >= 44, "Input WAV is shorter than its required 44-byte header"
    payload = raw[44:]
    assert len(payload) % 2 == 0, "16-bit PCM payload has an odd byte count"
    samples = struct.unpack("<%dh" % (len(payload) // 2), payload)
    reduced = [v // 2 if v >= 0 else -((-v) // 2) for v in samples]
    return raw[:44] + struct.pack("<%dh" % len(reduced), *reduced)


def get(url, attempts=1):
    last = None
    for _ in range(attempts):
        try:
            return requests.get(url, timeout=3)
        except requests.RequestException as exc:
            last = exc
            time.sleep(0.15)
    pytest.fail(f"Failed to connect to {url}: {last}")


def socket_owners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def proc_exe(pid):
    return os.path.realpath(f"/proc/{pid}/exe")


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled native executable"


def find_c_sources():
    found = []
    for root in ("/home/user", "/app", "/root", "/tmp"):
        if not os.path.isdir(root):
            continue
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "verifier_build"}]
            for name in files:
                path = os.path.join(base, name)
                if name.endswith(".c") and os.path.isfile(path):
                    found.append(path)
    return sorted(set(found))


def compile_candidates(sources):
    build = "/tmp/verifier_build"
    os.makedirs(build, exist_ok=True)
    groups = [(src,) for src in sources]
    by_dir = {}
    for src in sources:
        by_dir.setdefault(os.path.dirname(src), []).append(src)
    groups.extend(tuple(v) for v in by_dir.values() if len(v) > 1)

    binaries = []
    seen = set()
    for i, group in enumerate(groups):
        group = tuple(sorted(group))
        if group in seen:
            continue
        seen.add(group)
        output = os.path.join(build, f"candidate_{i}")
        cmd = ["gcc", "-O2", "-o", output, *group, "-lm", "-pthread"]
        try:
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    timeout=15)
        except subprocess.TimeoutExpired:
            continue
        if result.returncode == 0 and os.path.isfile(output):
            assert_elf(output)
            binaries.append(output)
    return binaries


def terminate_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_final_state():
    # Preserve the original verifier's file, HTTP, WAV-length, and MSE assertions.
    assert os.path.exists(QUIET), f"The file {QUIET} does not exist."
    assert os.path.isfile(QUIET), f"The path {QUIET} is not a file."
    assert os.path.exists(RAW), f"Original file {RAW} is missing."

    with open(RAW, "rb") as f:
        raw = f.read()
    with open(QUIET, "rb") as f:
        quiet = f.read()
    expected = halved_wav(raw)

    # The header and every sample must be exact, not merely within an MSE tolerance.
    assert quiet[:44] == raw[:44], "The output WAV header is not an exact 44-byte copy"
    assert quiet == expected, "The output samples are not exactly divided by two toward zero"

    resp9090 = get(URL_9090)
    assert resp9090.status_code == 200, f"Expected HTTP 200 OK, got {resp9090.status_code}"
    assert "audio/wav" in resp9090.headers.get("Content-Type", "").lower()
    assert int(resp9090.headers.get("Content-Length", "-1")) == len(quiet)
    assert resp9090.content == quiet, "Port 9090 did not serve the exact output file"

    resp8080 = get(URL_8080)
    assert resp8080.status_code == 200
    assert "audio/wav" in resp8080.headers.get("Content-Type", "").lower()
    assert int(resp8080.headers.get("Content-Length", "-1")) == len(quiet)
    assert resp8080.content == quiet, "The C server on port 8080 did not serve the output file"

    recv_path = "/tmp/test_received.wav"
    with open(recv_path, "wb") as f:
        f.write(resp9090.content)
    with wave.open(RAW, "rb") as w_in:
        orig_samples = np.frombuffer(w_in.readframes(w_in.getnframes()), dtype=np.int16)
        ref_samples = np.trunc(orig_samples / 2.0).astype(np.int16)
    with wave.open(recv_path, "rb") as w_recv:
        recv_samples = np.frombuffer(w_recv.readframes(w_recv.getnframes()), dtype=np.int16)
    assert len(recv_samples) > 0, "Received WAV file has no audio samples."
    assert len(recv_samples) == len(ref_samples), \
        f"Expected {len(ref_samples)} samples, got {len(recv_samples)}."
    mse = np.mean((ref_samples.astype(np.float32) - recv_samples.astype(np.float32)) ** 2)
    assert mse <= 1.0, f"MSE of audio samples is {mse:.4f}, which exceeds 1.0."

    sources = find_c_sources()
    assert sources, "No C source program was found in an agent-writable location"
    binaries = compile_candidates(sources)
    assert binaries, "The submitted C source could not be compiled"

    # Execute compiled submitted C code on verifier-derived PCM values, including
    # odd negatives where floor division would differ from rounding toward zero.
    test_samples = [-32768, -32767, -101, -3, -1, 0, 1, 2, 3, 100, 32766, 32767]
    payload = struct.pack("<%dh" % len(test_samples), *test_samples)
    data_size = len(payload)
    test_header = (b"RIFF" + struct.pack("<I", 36 + data_size) + b"WAVEfmt " +
                   struct.pack("<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16) +
                   b"data" + struct.pack("<I", data_size))
    test_raw = test_header + payload
    test_expected = halved_wav(test_raw)

    old_raw = raw
    old_quiet = quiet
    processor_binary = None
    try:
        with open(RAW, "wb") as f:
            f.write(test_raw)
        for binary in binaries:
            try:
                os.unlink(QUIET)
            except FileNotFoundError:
                pass
            try:
                proc = subprocess.Popen([binary], stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, start_new_session=True)
                try:
                    proc.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    terminate_group(proc)
            except OSError:
                continue
            if os.path.isfile(QUIET):
                with open(QUIET, "rb") as f:
                    made = f.read()
                if made == test_expected and made[:44] == test_header:
                    processor_binary = binary
                    break
        assert processor_binary is not None, \
            "No submitted C program produced the exact required WAV on verifier-derived samples"
    finally:
        with open(RAW, "wb") as f:
            f.write(old_raw)
        with open(QUIET, "wb") as f:
            f.write(old_quiet)

    # Confirm the required topology before replacing the server with a freshly
    # compiled copy of the submitted C implementation.
    owners8080 = socket_owners(8080)
    owners9090 = socket_owners(9090)
    assert owners8080, "No process is listening on TCP port 8080"
    assert owners9090, "No process is listening on TCP port 9090"
    for pid in owners8080:
        assert_elf(proc_exe(pid))
    socat_pids = [pid for pid in owners9090 if os.path.basename(proc_exe(pid)).startswith("socat")]
    assert socat_pids, "TCP port 9090 is not owned by socat"
    for pid in socat_pids:
        cmd = proc_cmdline(pid)
        assert "9090" in cmd and "8080" in cmd, \
            f"socat command does not describe a 9090-to-8080 forward: {cmd}"

    # Stop the original 8080 listener, then compile and run submitted C source.
    # It must itself own port 8080 and remain reachable through the existing socat tunnel.
    for pid in owners8080:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in socket_owners(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)

    working_server = None
    for binary in binaries:
        proc = subprocess.Popen([binary], stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
        ok = False
        for _ in range(20):
            time.sleep(0.15)
            owners = socket_owners(8080)
            matching = []
            for pid in owners:
                try:
                    if os.path.samefile(proc_exe(pid), binary):
                        matching.append(pid)
                except (FileNotFoundError, ProcessLookupError, OSError):
                    pass
            if not matching:
                continue
            try:
                direct = requests.get(URL_8080, timeout=1)
                forwarded = requests.get(URL_9090, timeout=1)
                ok = (direct.status_code == 200 and forwarded.status_code == 200 and
                      direct.headers.get("Content-Type", "").lower().find("audio/wav") >= 0 and
                      int(direct.headers.get("Content-Length", "-1")) == len(old_quiet) and
                      direct.content == old_quiet and forwarded.content == old_quiet)
            except (requests.RequestException, ValueError):
                ok = False
            if ok:
                break
        if ok:
            working_server = proc
            break
        terminate_group(proc)
        for pid in socket_owners(8080):
            try:
                if os.path.samefile(proc_exe(pid), binary):
                    os.kill(pid, signal.SIGKILL)
            except (FileNotFoundError, ProcessLookupError, OSError):
                pass

    assert working_server is not None, \
        "No submitted C server listened on 127.0.0.1:8080 and served the WAV through socat on 9090"


if __name__ == "__main__":
    test_final_state()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
