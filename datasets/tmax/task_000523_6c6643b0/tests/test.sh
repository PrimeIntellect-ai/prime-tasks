#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/analyze_exfil.sh"


def test_analyze_exfil_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_required_sandbox_command_is_present():
    with open(SCRIPT_PATH, "r", errors="replace") as f:
        script = f.read()
    assert re.search(r"(^|[/'\"[:space:]])bwrap([[:space:]]|$)", script), \
        "The malware must be executed using bwrap."
    assert "--unshare-net" in script, "bwrap must disable network access with --unshare-net."


def make_case(root, index):
    case_dir = os.path.join(root, f"case_{index}")
    os.makedirs(case_dir)

    token = "heldout_" + secrets.token_hex(12)
    key = secrets.token_hex(32)
    iv = secrets.token_hex(16)
    payload = (
        "GET /private HTTP/1.1\r\n"
        "Host: heldout.example\r\n"
        f"Cookie: theme=dark; Session-Token={token}; mode=test\r\n"
        "Connection: close\r\n\r\n"
    ).encode()

    encrypted = subprocess.check_output([
        "openssl", "enc", "-aes-256-cbc", "-K", key, "-iv", iv
    ], input=payload)
    import base64
    displayed = base64.b64encode(encrypted).decode("ascii")

    video = os.path.join(case_dir, "capture.mp4")
    drawtext = (
        "drawtext=fontfile=/usr/share/fonts/truetype/liberation/"
        "LiberationMono-Regular.ttf:fontsize=28:fontcolor=white:"
        f"x=30:y=120:text={displayed}"
    )
    subprocess.run([
        "ffmpeg", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "color=c=black:s=2560x320:r=1:d=0.8",
        "-vf", drawtext, "-c:v", "libx264", "-pix_fmt", "yuv420p", video
    ], check=True)

    host_net_inode = os.stat("/proc/self/ns/net").st_ino
    probe = f"/heldout_bwrap_probe_{secrets.token_hex(8)}"
    source = os.path.join(case_dir, "service.c")
    malware = os.path.join(case_dir, "suspicious_service")
    code = r'''
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

int main(void) {
    struct stat st;
    int isolated_net = 0;
    if (stat("/proc/self/ns/net", &st) == 0 &&
        (unsigned long long)st.st_ino != %dULL) {
        isolated_net = 1;
    }

    int fd = open("%s", O_WRONLY | O_CREAT | O_EXCL, 0600);
    int readonly_root = (fd < 0);
    if (fd >= 0) {
        close(fd);
        unlink("%s");
    }

    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd >= 0) {
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(9);
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
        connect(sockfd, (struct sockaddr *)&addr, sizeof(addr));
        close(sockfd);
    }

    if (!isolated_net || !readonly_root) {
        puts("Sandbox safety checks failed.");
        return 3;
    }

    printf("KEY: %s\n");
    printf("IV: %s\n");
    return 0;
}
''' % (host_net_inode, probe, probe, key, iv)

    with open(source, "w") as f:
        f.write(code)
    subprocess.run(["gcc", "-O2", source, "-o", malware], check=True)
    os.unlink(source)
    os.chmod(malware, 0o755)
    return video, malware, token


def test_exfil_accuracy():
    root = tempfile.mkdtemp(prefix="exfil-heldout-")
    try:
        test_cases = [make_case(root, i) for i in range(5)]
        correct = 0
        total = len(test_cases)
        assert total > 0, "No expected tokens found in test cases."

        for video, malware, expected in test_cases:
            try:
                out = subprocess.check_output(
                    ["bash", SCRIPT_PATH, video, malware],
                    timeout=120,
                    text=True,
                )
                extracted = [line.strip() for line in out.splitlines() if line.strip()]
                if expected in extracted:
                    correct += 1
            except subprocess.TimeoutExpired:
                print(f"Timed out processing {video}")
            except subprocess.CalledProcessError as e:
                print(f"Error processing {video}: exit status {e.returncode}")

        accuracy = correct / total
        assert accuracy >= 0.8, (
            f"Accuracy metric failed: {accuracy:.2f} < 0.8 threshold. "
            f"Correct: {correct}/{total}"
        )
    finally:
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
