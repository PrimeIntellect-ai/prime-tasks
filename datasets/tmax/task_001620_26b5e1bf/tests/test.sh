#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import difflib
import os
import random
import re
import secrets
import string
import subprocess

import pytest


def test_target_txt_correct():
    target_path = "/app/target.txt"
    assert os.path.isfile(target_path), f"Missing target file: {target_path}"

    with open(target_path, "r") as f:
        content = f.read().strip()

    expected_path = "/root/.ssh/authorized_keys"
    assert content == expected_path, f"Expected '{expected_path}' in {target_path}, but got '{content}'"


def test_server_fixed_binary_exists():
    binary_path = "/app/server_fixed"
    assert os.path.isfile(binary_path), f"Missing compiled binary: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary is not executable: {binary_path}"


def test_server_c_logic():
    server_c_path = "/app/server.c"
    assert os.path.isfile(server_c_path), f"Missing source code: {server_c_path}"

    with open(server_c_path, "r") as f:
        src = f.read()

    # Rename the student's main function so we can compile our own test harness.
    src_modified = src.replace("int main", "int student_main")

    harness = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int handle_upload(const char* filename, const char* content);

int main(int argc, char **argv) {
    if (argc != 8) return 90;
    system("mkdir -p /app/uploads");

    /* Preserve the original three behavioral assertions. */
    int res1 = handle_upload("../evil.txt", "bad");
    int res2 = handle_upload("/etc/evil.txt", "bad");
    int res3 = handle_upload("good.txt", "good");

    if (res1 != -1) return 1;
    if (res2 != -1) return 2;
    if (res3 != 0) return 3;

    /* Exercise unpredictable names so the three fixed cases cannot be hardcoded. */
    remove(argv[4]);
    remove(argv[5]);
    remove(argv[6]);

    int res4 = handle_upload(argv[1], argv[7]);
    int res5 = handle_upload(argv[2], argv[7]);
    int res6 = handle_upload(argv[3], argv[7]);

    if (res4 != -1 || access(argv[4], F_OK) == 0) return 4;
    if (res5 != -1 || access(argv[5], F_OK) == 0) return 5;
    if (res6 != 0) return 6;

    FILE *f = fopen(argv[6], "r");
    if (!f) return 7;
    char buf[512] = {0};
    if (!fgets(buf, sizeof(buf), f)) {
        fclose(f);
        return 8;
    }
    fclose(f);
    if (strcmp(buf, argv[7]) != 0) return 9;

    return 0;
}
'''
    test_src_path = "/tmp/test_server.c"
    test_bin_path = "/tmp/test_server"

    with open(test_src_path, "w") as f:
        f.write(src_modified + "\n" + harness)

    compile_res = subprocess.run(
        ["gcc", "-o", test_bin_path, test_src_path],
        capture_output=True,
        text=True,
    )
    assert compile_res.returncode == 0, (
        f"Failed to compile test harness with server.c:\n{compile_res.stderr}"
    )

    token = secrets.token_hex(12)
    subdir = f"dir_{token}"
    traversal_leaf = f"traversal_{token}.txt"
    absolute_leaf = f"absolute_{token}.txt"
    valid_leaf = f"valid_{token}.txt"
    traversal_name = f"{subdir}/../{traversal_leaf}"
    absolute_name = f"/{absolute_leaf}"
    valid_name = valid_leaf
    traversal_output = f"/app/uploads/{traversal_leaf}"
    absolute_output = f"/app/uploads/{absolute_leaf}"
    valid_output = f"/app/uploads/{valid_leaf}"
    content = f"dynamic-content-{token}"
    os.makedirs(f"/app/uploads/{subdir}", exist_ok=True)

    run_res = subprocess.run([
        test_bin_path,
        traversal_name,
        absolute_name,
        valid_name,
        traversal_output,
        absolute_output,
        valid_output,
        content,
    ])

    failures = {
        1: "server.c handle_upload did not reject filename containing '../'",
        2: "server.c handle_upload did not reject filename starting with '/'",
        3: "server.c handle_upload rejected a valid filename",
        4: "server.c did not reject a dynamically generated '../' filename without writing",
        5: "server.c did not reject a dynamically generated absolute filename without writing",
        6: "server.c rejected a dynamically generated valid filename",
        7: "server.c did not create the valid upload",
        8: "server.c created an unreadable or empty valid upload",
        9: "server.c did not preserve the valid upload content",
    }
    if run_res.returncode in failures:
        pytest.fail(failures[run_res.returncode])
    assert run_res.returncode == 0, (
        f"server.c handle_upload test harness failed with exit code {run_res.returncode}"
    )


def redact_reference(text):
    cc = re.compile(r"(?:[0-9]{16}|[0-9]{4}(?:-[0-9]{4}){3})")
    password = re.compile(r"password=[^& ]*([& ])")
    text = cc.sub("[REDACTED_CC]", text)
    return password.sub(r"password=[REDACTED]\1", text)


def test_redact_sh_accuracy():
    script_path = "/app/redact.sh"
    assert os.path.isfile(script_path), f"Missing redaction script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Redaction script is not executable: {script_path}"

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits

    def rand_text(length):
        return "".join(rng.choice(alphabet) for _ in range(length))

    lines = []
    for i in range(180):
        password = rand_text(rng.randint(12, 28))
        digits = "".join(rng.choice(string.digits) for _ in range(16))
        hyphenated = "-".join(digits[j:j + 4] for j in range(0, 16, 4))
        ip = ".".join(str(rng.randint(1, 254)) for _ in range(4))
        suffix = rand_text(rng.randint(5, 16))
        mode = i % 4
        if mode == 0:
            lines.append(
                f"{ip} GET /login?user={rand_text(8)}&password={password}&next={suffix} card={digits}\n"
            )
        elif mode == 1:
            lines.append(
                f"{ip} POST /pay password={password} CC:{hyphenated} ref={suffix}\n"
            )
        elif mode == 2:
            lines.append(
                f"{ip} audit password={password}&primary={digits} backup={hyphenated} end\n"
            )
        else:
            # Benign near-matches ensure unrelated data is preserved.
            lines.append(
                f"{ip} note passwordish={password}& short=123456789012345 id={suffix}\n"
            )

    eval_text = "".join(lines)
    golden_out = redact_reference(eval_text)
    eval_log = f"/tmp/redact_eval_{secrets.token_hex(12)}.log"
    with open(eval_log, "w") as f:
        f.write(eval_text)

    try:
        result = subprocess.run(
            [script_path, eval_log], capture_output=True, text=True, timeout=20
        )
    finally:
        os.remove(eval_log)

    assert result.returncode == 0, (
        f"{script_path} failed to execute properly.\nStderr: {result.stderr}"
    )

    agent_out = result.stdout
    matcher = difflib.SequenceMatcher(None, agent_out, golden_out)
    accuracy = matcher.ratio()
    assert accuracy >= 0.95, (
        f"Redaction accuracy {accuracy:.4f} is below the threshold of 0.95"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
