#!/bin/bash
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/capture_unlink.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

static int write_all(int fd, const void *buf, size_t len) {
    const char *p = (const char *)buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n <= 0) return -1;
        p += n;
        len -= (size_t)n;
    }
    return 0;
}

int unlink(const char *pathname) {
    static int (*real_unlink)(const char *) = NULL;
    if (!real_unlink)
        real_unlink = dlsym(RTLD_NEXT, "unlink");

    const char *fd_text = getenv("VERIFIER_CAPTURE_FD");
    if (fd_text && pathname) {
        size_t path_len = strlen(pathname);
        if (path_len >= 4 && strcmp(pathname + path_len - 4, ".dat") == 0) {
            int input = open(pathname, O_RDONLY);
            if (input >= 0) {
                struct stat st;
                if (fstat(input, &st) == 0 && st.st_size >= 0 && st.st_size <= 1048576) {
                    uint32_t data_len = (uint32_t)st.st_size;
                    unsigned char *data = malloc(data_len ? data_len : 1);
                    size_t used = 0;
                    while (used < data_len) {
                        ssize_t n = read(input, data + used, data_len - used);
                        if (n <= 0) break;
                        used += (size_t)n;
                    }
                    if (used == data_len) {
                        const char *base = strrchr(pathname, '/');
                        base = base ? base + 1 : pathname;
                        uint32_t name_len = (uint32_t)strlen(base);
                        int output = atoi(fd_text);
                        uint32_t header[2] = {name_len, data_len};
                        write_all(output, header, sizeof(header));
                        write_all(output, base, name_len);
                        write_all(output, data, data_len);
                    }
                    free(data);
                }
                close(input);
            }
        }
    }

    return real_unlink(pathname);
}
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import shutil
import signal
import struct
import subprocess
import threading
import time


def read_exact(stream, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = stream.read(remaining)
        if not chunk:
            return None
        chunks.append(chunk)
        remaining -= len(chunk)
    return b''.join(chunks)


def test_rescue_script_metric():
    script_path = '/home/user/rescue.sh'
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Script {script_path} is not a regular file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    workspace = '/home/user/workspace'
    rescued = '/home/user/rescued_data'
    for path in (workspace, rescued):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
        os.makedirs(path)

    captured = {}
    read_fd, write_fd = os.pipe()

    def collect():
        with os.fdopen(read_fd, 'rb', buffering=0) as stream:
            while True:
                header = read_exact(stream, 8)
                if header is None:
                    return
                name_len, data_len = struct.unpack('=II', header)
                assert 0 < name_len < 4096
                assert data_len <= 1048576
                name = read_exact(stream, name_len)
                data = read_exact(stream, data_len)
                assert name is not None and data is not None
                captured[name.decode('utf-8')] = data

    collector = threading.Thread(target=collect, daemon=True)
    collector.start()

    agent_proc = subprocess.Popen(
        ['nohup', script_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid
    )

    try:
        time.sleep(1)
        processor_path = '/app/proprietary_processor'
        assert os.path.exists(processor_path), f"Processor binary missing at {processor_path}."
        assert os.access(processor_path, os.X_OK), f"Processor binary is not executable: {processor_path}."

        env = os.environ.copy()
        env['LD_PRELOAD'] = '/tmp/capture_unlink.so'
        env['VERIFIER_CAPTURE_FD'] = str(write_fd)
        processor = subprocess.Popen(
            [processor_path, workspace],
            env=env,
            pass_fds=(write_fd,)
        )
        os.close(write_fd)
        write_fd = None
        assert processor.wait() == 0, 'Processor execution failed.'
        collector.join(timeout=10)
        assert not collector.is_alive(), 'Timed out collecting processor output.'
    finally:
        if write_fd is not None:
            os.close(write_fd)
        try:
            os.killpg(os.getpgid(agent_proc.pid), signal.SIGKILL)
        except Exception:
            pass
        try:
            agent_proc.wait(timeout=5)
        except Exception:
            pass
        subprocess.run(['pkill', '-f', 'inotifywait'], capture_output=True)

    assert len(captured) == 1000, f"Verifier captured {len(captured)} generated files, expected 1000."
    oracle_hashes = {name: hashlib.sha256(data).hexdigest() for name, data in captured.items()}

    manifest_path = os.path.join(rescued, 'manifest.txt')
    assert os.path.exists(manifest_path), f"Manifest file {manifest_path} was not created."

    valid_count = 0
    seen_files = set()
    with open(manifest_path, 'r', encoding='utf-8', errors='replace') as manifest:
        for line in manifest:
            parts = line.strip().split()
            if len(parts) < 2:
                continue
            expected_hash = parts[0]
            filename = parts[1]
            basename = os.path.basename(filename)
            if basename in seen_files or basename not in oracle_hashes:
                continue

            filepath = os.path.join(rescued, basename)
            if not os.path.isfile(filepath):
                continue
            with open(filepath, 'rb') as dat:
                actual_hash = hashlib.sha256(dat.read()).hexdigest()

            if actual_hash == expected_hash and actual_hash == oracle_hashes[basename]:
                seen_files.add(basename)
                valid_count += 1

    assert valid_count >= 850, (
        f"Metric threshold failed: Rescued {valid_count} intact processor-generated files, "
        "expected at least 850."
    )
TEST_EOF

if gcc -shared -fPIC -O2 /tmp/capture_unlink.c -o /tmp/capture_unlink.so -ldl && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
