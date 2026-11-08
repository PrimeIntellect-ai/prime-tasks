#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
import time


def test_dnsmasq_config():
    conf_path = "/home/user/sandbox/dnsmasq.conf"
    assert os.path.exists(conf_path), f"Missing {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()
    assert re.search(r"address=/c2-malware\.local/127\.0\.0\.1", content), \
        "dnsmasq.conf does not correctly resolve c2-malware.local to 127.0.0.1"


def test_nginx_config():
    conf_path = "/home/user/sandbox/nginx.conf"
    assert os.path.exists(conf_path), f"Missing {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()
    assert re.search(r"listen\s+8080", content), \
        "nginx.conf does not contain a listen directive for port 8080"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:5000", content), \
        "nginx.conf does not contain a proxy_pass directive to http://127.0.0.1:5000"


def _stop_sandbox():
    subprocess.run(["pkill", "-f", "/home/user/sandbox/sinkhole.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "dnsmasq"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def test_sandbox_end_to_end():
    _stop_sandbox()
    try:
        started = subprocess.run(
            ["bash", "/home/user/sandbox/start_sandbox.sh"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert started.returncode == 0, f"start_sandbox.sh failed: {started.stderr}"

        deadline = time.time() + 8
        last_error = "services did not become ready"
        while time.time() < deadline:
            dns = subprocess.run(
                ["dig", "+short", "+time=1", "+tries=1", "@127.0.0.1", "c2-malware.local", "A"],
                capture_output=True,
                text=True,
            )
            try:
                web = subprocess.run(
                    ["curl", "--noproxy", "*", "--silent", "--show-error", "--fail", "--max-time", "2",
                     "--resolve", "c2-malware.local:8080:127.0.0.1", "http://c2-malware.local:8080/ping"],
                    capture_output=True,
                    text=True,
                    timeout=3,
                )
            except subprocess.TimeoutExpired:
                web = None

            if dns.returncode == 0 and dns.stdout.strip() == "127.0.0.1" and web and web.returncode == 0:
                try:
                    assert json.loads(web.stdout) == {"status": "sinkholed"}
                    return
                except Exception as exc:
                    last_error = f"bad sinkhole response {web.stdout!r}: {exc}"
            else:
                last_error = f"DNS={dns.stdout!r}/{dns.stderr!r}, HTTP={None if web is None else (web.returncode, web.stdout, web.stderr)}"
            time.sleep(0.25)
        raise AssertionError(f"sandbox flow failed: {last_error}")
    finally:
        _stop_sandbox()


def test_parser_fixed_exists_and_executable():
    parser_path = "/home/user/evidence/parser_fixed"
    assert os.path.exists(parser_path), f"Fixed parser binary missing at {parser_path}"
    assert os.path.isfile(parser_path), f"Fixed parser at {parser_path} is not a regular file"
    assert os.access(parser_path, os.X_OK), f"Fixed parser at {parser_path} is not executable"
    with open(parser_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "parser_fixed must be a compiled ELF binary"

    with tempfile.TemporaryDirectory() as td:
        for length in (0, 1, 31, 127, 255):
            payload = os.path.join(td, secrets.token_hex(12))
            with open(payload, "wb") as f:
                f.write(bytes([random.randrange(256), length]) + os.urandom(length))
            result = subprocess.run([parser_path, payload], capture_output=True, timeout=2)
            assert result.returncode == 0, f"parser_fixed failed on a length-{length} payload"


def test_parser_source_boundary_and_termination_fix():
    source = "/home/user/evidence/parser.c"
    assert os.path.isfile(source), f"Missing {source}"
    with tempfile.TemporaryDirectory() as td:
        obj = os.path.join(td, "parser.o")
        harness = os.path.join(td, "harness.c")
        binary = os.path.join(td, "harness")
        with open(harness, "w") as f:
            f.write(r'''
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
int parse_payload(unsigned char *payload);
int main(void) {
    long page = sysconf(_SC_PAGESIZE);
    unsigned char *mem = mmap(NULL, page * 2, PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) return 90;
    if (mprotect(mem + page, page, PROT_NONE) != 0) return 91;
    unsigned int len = 73;
    unsigned char *payload = mem + page - (2 + len);
    payload[0] = 0;
    payload[1] = (unsigned char)len;
    memset(payload + 2, 0x41, len);
    return parse_payload(payload);
}
''')
        compile_obj = subprocess.run(
            ["gcc", "-O0", "-Dmain=parser_program_main", "-c", source, "-o", obj],
            capture_output=True,
            text=True,
        )
        assert compile_obj.returncode == 0, f"parser.c does not compile: {compile_obj.stderr}"
        compile_harness = subprocess.run(
            ["gcc", "-O0", harness, obj, "-o", binary], capture_output=True, text=True
        )
        assert compile_harness.returncode == 0, f"Could not link parser test harness: {compile_harness.stderr}"
        run = subprocess.run([binary], capture_output=True, timeout=2)
        assert run.returncode == 0, "parse_payload still reads beyond the declared chunk or fails to terminate"


def test_classifier_accuracy():
    classifier_path = "/home/user/classifier.py"
    assert os.path.exists(classifier_path), f"Classifier script missing at {classifier_path}"

    evil_dir = "/app/verifier/corpus/evil"
    clean_dir = "/app/verifier/corpus/clean"
    assert os.path.exists(evil_dir), f"Evil corpus missing at {evil_dir}"
    assert os.path.exists(clean_dir), f"Clean corpus missing at {clean_dir}"

    evil_files = os.listdir(evil_dir)
    clean_files = os.listdir(clean_dir)
    evil_failed = []
    for name in evil_files:
        path = os.path.join(evil_dir, name)
        res = subprocess.run(["python3", classifier_path, path], capture_output=True, text=True)
        if res.stdout.strip() != "EVIL":
            evil_failed.append(name)
    clean_failed = []
    for name in clean_files:
        path = os.path.join(clean_dir, name)
        res = subprocess.run(["python3", classifier_path, path], capture_output=True, text=True)
        if res.stdout.strip() != "CLEAN":
            clean_failed.append(name)
    assert not evil_failed, f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {evil_failed[:5]}"
    assert not clean_failed, f"{len(clean_failed)} of {len(clean_files)} clean modified (flagged incorrectly): {clean_failed[:5]}"


def test_classifier_on_unlabeled_generated_samples():
    classifier = "/home/user/classifier.py"
    assert os.path.isfile(classifier), f"Classifier script missing at {classifier}"
    cases = []
    with tempfile.TemporaryDirectory(prefix="payloads_") as td:
        for _ in range(120):
            length = random.randint(10, 200)
            path = os.path.join(td, secrets.token_hex(16))
            with open(path, "wb") as f:
                f.write(bytes([random.randrange(256), length]) + os.urandom(length + 5))
            cases.append((path, "CLEAN"))
        for _ in range(120):
            path = os.path.join(td, secrets.token_hex(16))
            with open(path, "wb") as f:
                f.write(bytes([random.randrange(256), 255]) + os.urandom(260))
            cases.append((path, "EVIL"))

        random.shuffle(cases)
        failures = []
        for path, expected in cases:
            try:
                res = subprocess.run(
                    ["python3", classifier, path], capture_output=True, text=True, timeout=2
                )
            except subprocess.TimeoutExpired:
                failures.append((os.path.basename(path), expected, "timeout"))
                continue
            if res.returncode != 0 or res.stdout != expected + "\n":
                failures.append((os.path.basename(path), expected, res.returncode, res.stdout, res.stderr))
        assert not failures, f"Classifier failed generated content-based cases: {failures[:5]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
