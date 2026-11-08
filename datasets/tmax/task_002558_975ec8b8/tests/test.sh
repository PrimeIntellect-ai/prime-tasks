#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import ctypes.util
import hashlib
import os
import re
import shutil
import subprocess
import time


def run(cmd, timeout=30):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def lz4_frame_digest(path):
    libname = ctypes.util.find_library("lz4")
    assert libname, "The system LZ4 library needed to validate archives is unavailable"
    lib = ctypes.CDLL(libname)

    lib.LZ4F_createDecompressionContext.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_uint]
    lib.LZ4F_createDecompressionContext.restype = ctypes.c_size_t
    lib.LZ4F_freeDecompressionContext.argtypes = [ctypes.c_void_p]
    lib.LZ4F_freeDecompressionContext.restype = ctypes.c_size_t
    lib.LZ4F_decompress.argtypes = [
        ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t),
        ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p
    ]
    lib.LZ4F_decompress.restype = ctypes.c_size_t
    lib.LZ4F_isError.argtypes = [ctypes.c_size_t]
    lib.LZ4F_isError.restype = ctypes.c_uint
    lib.LZ4F_getErrorName.argtypes = [ctypes.c_size_t]
    lib.LZ4F_getErrorName.restype = ctypes.c_char_p

    data = open(path, "rb").read()
    assert data, f"Archive {path} is empty"
    src = ctypes.create_string_buffer(data, len(data))
    dctx = ctypes.c_void_p()
    result = lib.LZ4F_createDecompressionContext(ctypes.byref(dctx), 100)
    assert not lib.LZ4F_isError(result), "Could not create an LZ4 frame decompressor"

    digest = hashlib.sha256()
    total = 0
    pos = 0
    finished = False
    try:
        while pos < len(data):
            dst = ctypes.create_string_buffer(1024 * 1024)
            dst_size = ctypes.c_size_t(len(dst))
            src_size = ctypes.c_size_t(len(data) - pos)
            result = lib.LZ4F_decompress(
                dctx, dst, ctypes.byref(dst_size),
                ctypes.cast(ctypes.byref(src, pos), ctypes.c_void_p),
                ctypes.byref(src_size), None
            )
            if lib.LZ4F_isError(result):
                name = lib.LZ4F_getErrorName(result).decode("utf-8", errors="replace")
                raise AssertionError(f"{path} is not a valid LZ4 frame: {name}")
            assert src_size.value or dst_size.value or result == 0, "LZ4 decoder made no progress"
            pos += src_size.value
            if dst_size.value:
                digest.update(dst.raw[:dst_size.value])
                total += dst_size.value
            if result == 0:
                finished = True
                break
    finally:
        lib.LZ4F_freeDecompressionContext(dctx)

    assert finished, f"Archive {path} ended before its LZ4 frame was complete"
    assert pos == len(data), f"Archive {path} contains unexpected trailing data"
    return digest.hexdigest(), total


def file_digest(path):
    h = hashlib.sha256()
    size = 0
    with open(path, "rb") as f:
        while True:
            block = f.read(1024 * 1024)
            if not block:
                break
            h.update(block)
            size += len(block)
    return h.hexdigest(), size


def test_expect_script_exists():
    script_path = "/opt/auto_init.exp"
    assert os.path.isfile(script_path), f"Expect script {script_path} does not exist"
    content = open(script_path).read()
    assert os.access(script_path, os.X_OK) or "expect" in content, f"{script_path} does not appear to be a valid expect script"
    assert re.search(r"\bspawn\b[^\n]*?/opt/init_backup\.sh", content), "Expect script does not spawn /opt/init_backup.sh"
    assert re.search(r"\bexpect\b", content) and "Initialize backup directory" in content, "Expect script does not wait for the initialization prompt"
    assert re.search(r"\bsend(?:_user)?\b[^\n]*y", content), "Expect script does not send y to the prompt"

    shutil.rmtree("/backup", ignore_errors=True)
    result = run(["/usr/bin/expect", script_path], timeout=10)
    assert result.returncode == 0, f"Expect script failed or did not exit cleanly: {result.stdout}{result.stderr}"
    assert os.path.isdir("/backup"), "Expect script did not initialize /backup"


def test_service_file_updated():
    service_path = "/etc/systemd/system/log-archiver.service"
    assert os.path.isfile(service_path), f"Service file {service_path} does not exist"
    content = open(service_path).read()
    assert "auto_init.exp" in content, "The log-archiver.service was not updated to use the expect script (/opt/auto_init.exp)"


def test_source_and_makefile_fixes_present():
    source = "/app/lz4-1.9.4/programs/lz4io.c"
    assert os.path.isfile(source), f"Missing vendored source file {source}"
    content = open(source).read()
    assert not re.search(r"#\s*define\s+LZ4_IO_BUFFER_SIZE\s*\(?\s*1\s*\)?", content), "The one-byte LZ4 I/O buffer perturbation is still present"

    macro = re.search(r"#\s*define\s+LZ4_IO_BUFFER_SIZE\s+([^\n/]+)", content)
    if macro:
        expression = macro.group(1).strip()
        assert re.fullmatch(r"[0-9() *+<]+", expression), "LZ4_IO_BUFFER_SIZE is not a recognizable constant expression"
        value = eval(expression, {"__builtins__": {}}, {})
        assert value >= 64 * 1024, f"LZ4_IO_BUFFER_SIZE remains too small ({value} bytes)"
    else:
        assert re.search(r"(?:64|128|256|512|1024)\s*\*\s*1024|1\s*<<\s*(?:16|17|18|19|20)", content), "No restored I/O buffer of at least 64KB was found in lz4io.c"

    for makefile in ["/app/lz4-1.9.4/Makefile", "/app/lz4-1.9.4/programs/Makefile"]:
        text = open(makefile).read()
        assert "-O3" in text, f"Optimization was not restored in {makefile}"
        assert "-O0" not in text, f"Disabled optimization (-O0) remains in {makefile}"


def test_lz4_functionality_and_compression():
    lz4_bin = "/usr/local/bin/lz4"
    assert os.path.isfile(lz4_bin), f"Compiled binary {lz4_bin} does not exist"
    assert os.access(lz4_bin, os.X_OK), f"Compiled binary {lz4_bin} is not executable"
    with open(lz4_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{lz4_bin} is not a compiled ELF binary"

    input_file = "/tmp/lz4-functional-input.bin"
    archive = "/tmp/lz4-functional-input.lz4"
    restored = "/tmp/lz4-functional-restored.bin"
    seed = os.urandom(4096)
    with open(input_file, "wb") as f:
        for _ in range(2048):
            f.write(seed)

    result = run([lz4_bin, "-f", input_file, archive], timeout=20)
    assert result.returncode == 0, f"lz4 compression failed: {result.stderr}"
    assert os.path.isfile(archive), "lz4 did not create its output archive"
    assert os.path.getsize(archive) < os.path.getsize(input_file) // 4, "lz4 output does not actually compress highly repetitive data"

    expected = file_digest(input_file)
    assert lz4_frame_digest(archive) == expected, "An independent LZ4 decoder did not recover the original input"

    result = run([lz4_bin, "-d", "-f", archive, restored], timeout=20)
    assert result.returncode == 0, f"lz4 decompression failed: {result.stderr}"
    assert file_digest(restored) == expected, "The installed lz4 binary did not round-trip its archive"


def test_service_execution_success():
    subprocess.run(["systemctl", "daemon-reload"], capture_output=True)
    subprocess.run(["systemctl", "stop", "log-archiver.service"], capture_output=True)
    subprocess.run(["systemctl", "reset-failed", "log-archiver.service"], capture_output=True)
    os.makedirs("/backup", exist_ok=True)
    try:
        os.remove("/backup/messages.lz4")
    except FileNotFoundError:
        pass

    result = run(["systemctl", "start", "log-archiver.service"], timeout=30)
    assert result.returncode == 0, f"log-archiver.service failed to start: {result.stdout}{result.stderr}"

    status = run(["systemctl", "show", "log-archiver.service", "-p", "LoadState", "-p", "ActiveState", "-p", "Result", "-p", "ExecMainStatus"])
    assert status.returncode == 0, f"Could not query log-archiver.service: {status.stderr}"
    props = dict(line.split("=", 1) for line in status.stdout.splitlines() if "=" in line)
    assert props.get("LoadState") == "loaded", f"Service is not loaded: {props}"
    assert props.get("Result") == "success", f"Service did not report success: {props}"
    assert props.get("ExecMainStatus") == "0", f"Service archive command failed: {props}"

    backup_file = "/backup/messages.lz4"
    assert os.path.isfile(backup_file), f"The service did not run successfully; expected output {backup_file} is missing"
    assert lz4_frame_digest(backup_file) == file_digest("/var/log/messages"), "The service output is not a valid archive of /var/log/messages"


def test_summary_file_exists():
    summary_path = "/var/log/archiver_fix_summary.txt"
    assert os.path.isfile(summary_path), f"Summary file {summary_path} was not created"
    assert os.path.getsize(summary_path) > 0, f"Summary file {summary_path} is empty"


def test_lz4_performance_metric():
    lz4_bin = "/usr/local/bin/lz4"
    assert os.path.isfile(lz4_bin), f"Compiled binary {lz4_bin} does not exist"
    assert os.access(lz4_bin, os.X_OK), f"Compiled binary {lz4_bin} is not executable"

    input_file = "/tmp/test50m.bin"
    output_file = "/tmp/test50m.lz4"
    restored_file = "/tmp/test50m.restored"

    expected_hash = hashlib.sha256()
    with open(input_file, "wb") as f:
        for _ in range(50):
            block = os.urandom(1024 * 1024)
            expected_hash.update(block)
            f.write(block)

    start_time = time.perf_counter()
    res = subprocess.run([lz4_bin, "-f", input_file, output_file], capture_output=True)
    execution_time = time.perf_counter() - start_time

    assert res.returncode == 0, f"lz4 execution failed with error: {res.stderr.decode('utf-8', errors='ignore')}"
    assert os.path.isfile(output_file), f"lz4 failed to create the output file {output_file}"
    assert execution_time < 1.0, (
        f"Performance metric failed: lz4 execution time was {execution_time:.3f} seconds, "
        "which is >= the threshold of 1.0 seconds. The C code or Makefile optimization bug is not fully fixed."
    )

    expected = (expected_hash.hexdigest(), 50 * 1024 * 1024)
    assert lz4_frame_digest(output_file) == expected, "Performance output is not a valid LZ4 archive of the random input"

    res = run([lz4_bin, "-d", "-f", output_file, restored_file], timeout=30)
    assert res.returncode == 0, f"lz4 could not decompress its performance archive: {res.stderr}"
    assert file_digest(restored_file) == expected, "Decompressed performance archive does not match the generated input"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
