#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SRC_EOF' > /tmp/expected_uploader.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void decrypt(unsigned char *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        data[i] ^= 0x5A; // Simple XOR cipher
    }
}

// Insecure path traversal protection
void sanitize(char *filename) {
    char *pos;
    while ((pos = strstr(filename, "../")) != NULL) {
        memmove(pos, pos + 3, strlen(pos + 3) + 1);
        break; // BUG: Only removes the first occurrence
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <bundle.bin>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    size_t size = ftell(f);
    fseek(f, 0, SEEK_SET);

    unsigned char *buffer = malloc(size);
    fread(buffer, 1, size, f);
    fclose(f);

    decrypt(buffer, size);

    unsigned char name_len = buffer[0];
    char filename[256] = {0};
    memcpy(filename, buffer + 1, name_len);

    sanitize(filename);

    char filepath[512];
    snprintf(filepath, sizeof(filepath), "./uploads/%s", filename);

    FILE *out = fopen(filepath, "wb");
    if (out) {
        fwrite(buffer + 1 + name_len, 1, size - 1 - name_len, out);
        fclose(out);
        printf("File saved to %s\n", filepath);
    } else {
        printf("Failed to save file.\n");
    }

    free(buffer);
    return 0;
}
SRC_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess

WORKSPACE = "/home/user/workspace"


def test_exploit_payload_against_original_uploader():
    exploit = os.path.join(WORKSPACE, "exploit.bin")
    source = os.path.join(WORKSPACE, "uploader.c")
    expected_source = "/tmp/expected_uploader.c"
    target = os.path.join(WORKSPACE, "audit_success.txt")
    uploads = os.path.join(WORKSPACE, "uploads")

    assert os.path.isfile(source), "uploader.c is missing."
    with open(source, "rb") as actual, open(expected_source, "rb") as expected:
        assert actual.read() == expected.read(), "uploader.c was modified."

    assert os.path.exists(exploit), "exploit.bin does not exist."
    mode = os.lstat(exploit).st_mode
    assert stat.S_ISREG(mode), "exploit.bin must be a regular file."
    assert os.path.getsize(exploit) > 0, "exploit.bin is empty."

    if os.path.lexists(target):
        if os.path.isdir(target) and not os.path.islink(target):
            shutil.rmtree(target)
        else:
            os.unlink(target)

    if os.path.lexists(uploads):
        if os.path.isdir(uploads) and not os.path.islink(uploads):
            shutil.rmtree(uploads)
        else:
            os.unlink(uploads)
    os.mkdir(uploads)

    subprocess.run(
        ["gcc", "uploader.c", "-o", "uploader"],
        cwd=WORKSPACE,
        check=True,
        timeout=20,
    )
    result = subprocess.run(
        ["./uploader", "exploit.bin"],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        "uploader failed when processing exploit.bin: "
        + result.stderr.decode(errors="replace")
    )
    assert os.path.isfile(target) and not os.path.islink(target), (
        "Running uploader on exploit.bin did not create audit_success.txt "
        "outside the uploads directory."
    )
    with open(target, "rb") as f:
        assert f.read() == b"EXPLOITED", "The exploited file content is not exactly EXPLOITED."


def test_cwe_file_correct():
    path = "/home/user/workspace/cwe.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you create it?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "CWE-22", f"Expected '{path}' to contain 'CWE-22', but found '{content}'."


def test_audit_success_file_correct():
    path = "/home/user/workspace/audit_success.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The exploit did not successfully write the file."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "EXPLOITED", f"Expected '{path}' to contain 'EXPLOITED', but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
