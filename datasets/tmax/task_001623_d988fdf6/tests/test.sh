#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import textwrap
import pytest

PROJECT = "/home/user/gateway_test"
LOG = os.path.join(PROJECT, "qa_success.log")
EXE = os.path.join(PROJECT, "gateway_test")


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_run_submission():
    subprocess.run(["make", "clean"], cwd=PROJECT, check=True, timeout=30)
    subprocess.run(["make"], cwd=PROJECT, check=True, timeout=60)
    assert os.path.isfile(EXE), f"The executable {EXE} does not exist after make"
    assert os.access(EXE, os.X_OK), f"The file {EXE} is not executable"
    if os.path.exists(LOG):
        os.remove(LOG)
    subprocess.run([EXE], cwd=PROJECT, check=True, timeout=15)


def test_qa_success_log_exists():
    log_path = "/home/user/gateway_test/qa_success.log"
    assert os.path.isfile(log_path), (
        f"The verification log {log_path} does not exist. "
        "Did you compile and run the fixed executable?"
    )


def test_qa_success_log_content():
    log_path = "/home/user/gateway_test/qa_success.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"

    with open(log_path, 'r') as f:
        content = f.read()

    expected_substring = "Path: /api/v2/users, Param: SuperLongParameter1234567890, PackedSize:"
    assert expected_substring in content, (
        f"The log file {log_path} does not contain the expected output. "
        f"Expected to find '{expected_substring}' in the log file. "
        f"Actual content: {content}"
    )

    match = re.fullmatch(
        r"Path: /api/v2/users, Param: SuperLongParameter1234567890, PackedSize: (\d+)\n?",
        content,
    )
    assert match, f"Unexpected verification log format: {content!r}"
    path = "/api/v2/users"
    param = "SuperLongParameter1234567890"
    expected_size = 2 + len(path.encode()) + 2 + len(param.encode())
    assert int(match.group(1)) == expected_size, "Incorrect Protobuf packed size"


def test_gateway_executable_exists():
    exe_path = "/home/user/gateway_test/gateway_test"
    assert os.path.isfile(exe_path), (
        f"The executable {exe_path} does not exist. "
        "Did you run 'make' after fixing the code?"
    )
    assert os.access(exe_path, os.X_OK), (
        f"The file {exe_path} is not executable."
    )


def test_parser_is_memory_safe_and_really_serializes():
    harness_c = "/tmp/gateway_verifier_harness.c"
    gateway_o = "/tmp/gateway_submission.o"
    protobuf_o = "/tmp/gateway_pb.o"
    harness_exe = "/tmp/gateway_verifier_harness"

    with open(harness_c, "w") as f:
        f.write(textwrap.dedent(r'''
            #include <stdio.h>
            #include <stdlib.h>
            #include <string.h>
            #include "gateway.pb-c.h"

            void parse_url_and_route(const char *url);
            static const char *expected_path;
            static const char *expected_param;
            static int pack_was_checked;

            size_t __real_route_request__pack(const RouteRequest *message, uint8_t *out);

            size_t __wrap_route_request__pack(const RouteRequest *message, uint8_t *out) {
                if (!message || !message->path || !message->parameter ||
                    strcmp(message->path, expected_path) != 0 ||
                    strcmp(message->parameter, expected_param) != 0) {
                    fprintf(stderr, "Incorrect RouteRequest fields supplied to protobuf-c\n");
                    abort();
                }
                size_t n = __real_route_request__pack(message, out);
                RouteRequest *decoded = route_request__unpack(NULL, n, out);
                if (!decoded || !decoded->path || !decoded->parameter ||
                    strcmp(decoded->path, expected_path) != 0 ||
                    strcmp(decoded->parameter, expected_param) != 0) {
                    fprintf(stderr, "Serialized RouteRequest did not decode correctly\n");
                    abort();
                }
                route_request__free_unpacked(decoded, NULL);
                pack_was_checked = 1;
                return n;
            }

            int main(int argc, char **argv) {
                if (argc != 4) return 2;
                expected_path = argv[2];
                expected_param = argv[3];
                parse_url_and_route(argv[1]);
                if (!pack_was_checked) {
                    fprintf(stderr, "route_request__pack was not called\n");
                    return 3;
                }
                return 0;
            }
        '''))

    common = ["gcc", "-g", "-O0", "-fsanitize=address", "-fno-omit-frame-pointer", "-I", PROJECT]
    subprocess.run(
        common + ["-Dmain=gateway_submission_main", "-c", os.path.join(PROJECT, "gateway.c"), "-o", gateway_o],
        check=True, timeout=30,
    )
    subprocess.run(
        common + ["-c", os.path.join(PROJECT, "gateway.pb-c.c"), "-o", protobuf_o],
        check=True, timeout=30,
    )
    subprocess.run(
        common + [harness_c, gateway_o, protobuf_o, "-Wl,--wrap=route_request__pack", "-lprotobuf-c", "-o", harness_exe],
        check=True, timeout=30,
    )

    alphabet = string.ascii_letters + string.digits
    for _ in range(3):
        path = "/qa/" + "".join(secrets.choice(alphabet) for _ in range(12))
        param = "".join(secrets.choice(alphabet) for _ in range(28))
        url = path + "?param=" + param
        if os.path.exists(LOG):
            os.remove(LOG)
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        subprocess.run(
            [harness_exe, url, path, param], cwd=PROJECT, env=env,
            check=True, timeout=15,
        )
        assert os.path.isfile(LOG), "Parser did not generate qa_success.log"
        with open(LOG, "r") as f:
            content = f.read()
        expected_size = 2 + len(path.encode()) + 2 + len(param.encode())
        assert content == f"Path: {path}, Param: {param}, PackedSize: {expected_size}\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
