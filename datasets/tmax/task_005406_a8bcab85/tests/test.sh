#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pytest

CLASSIFIER_SCRIPT = "/home/user/classifier.py"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
WORK = Path(tempfile.mkdtemp(prefix="artifact_verifier_"))


def compile_c(source, output, extra=None):
    src = WORK / (output.name + ".c")
    src.write_text(source)
    cmd = ["gcc", "-O2", str(src), "-o", str(output)]
    if extra:
        cmd[1:1] = extra
    subprocess.run(cmd, check=True, capture_output=True)
    output.chmod(0o755)


def make_grpc_launcher(name, delay):
    server = WORK / (name + "_server.py")
    server.write_text(f'''import sys, time
from concurrent import futures
import grpc
import plugin_pb2
import plugin_pb2_grpc

class Service(plugin_pb2_grpc.PluginServiceServicer):
    def CheckHealth(self, request, context):
        time.sleep({delay!r})
        return plugin_pb2.HealthResponse(status="healthy")

server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
plugin_pb2_grpc.add_PluginServiceServicer_to_server(Service(), server)
if server.add_insecure_port("[::]:" + sys.argv[1]) == 0:
    raise SystemExit(2)
server.start()
server.wait_for_termination()
''')
    output = WORK / name
    py = json.dumps(sys.executable)
    server_path = json.dumps(str(server))
    compile_c(f'''#include <unistd.h>
int main(int argc, char **argv) {{
    if (argc != 2) return 2;
    execl({py}, "python3", {server_path}, argv[1], (char *)0);
    return 127;
}}
''', output)
    return output


def make_syscall(name, register):
    output = WORK / name
    if register == "rax":
        asm = 'mov $59, %%rax\\n\\tsyscall'
    else:
        asm = 'mov $0x3b, %%eax\\n\\tsyscall'
    compile_c(f'''int main(void) {{
    __asm__ volatile ("{asm}" ::: "rax", "memory");
    return 0;
}}
''', output)
    return output


def prepare_artifacts():
    subprocess.run([
        sys.executable, "-m", "grpc_tools.protoc", "-I/app",
        "--python_out=" + str(WORK),
        "--grpc_python_out=" + str(WORK),
        "/app/plugin.proto",
    ], check=True, capture_output=True)

    clean = make_grpc_launcher("known_clean", 0.0)
    slow = make_grpc_launcher("known_slow", 0.35)
    syscall_rax = make_syscall("known_execve_rax", "rax")
    syscall_eax = make_syscall("known_execve_eax", "eax")

    crash = WORK / "known_crash"
    compile_c('int main(void) { volatile int *p = (int *)0; *p = 1; return 0; }', crash)

    elf32 = WORK / "known_elf32"
    compile_c('int main(void) { return 0; }', elf32, ["-m32"])

    # Repair the contradictory fixed corpus before retaining the original checks:
    # clean files are functional plugins and every evil file has its stated defect.
    for i in range(1, 6):
        shutil.copy2(clean, Path(CLEAN_DIR) / f"clean_{i}")
    replacements = {
        "evil_1": elf32,
        "evil_2": syscall_rax,
        "evil_3": slow,
        "evil_4": crash,
        "evil_5": syscall_eax,
    }
    for name, source in replacements.items():
        shutil.copy2(source, Path(EVIL_DIR) / name)

    hidden = WORK / ("cases_" + os.urandom(8).hex())
    hidden.mkdir()

    hidden_clean = hidden / ("artifact_" + os.urandom(8).hex())
    shutil.copy2(clean, hidden_clean)

    hidden_slow = hidden / ("artifact_" + os.urandom(8).hex())
    shutil.copy2(slow, hidden_slow)

    hidden_rax = hidden / ("artifact_" + os.urandom(8).hex())
    shutil.copy2(syscall_rax, hidden_rax)

    hidden_eax = hidden / ("artifact_" + os.urandom(8).hex())
    shutil.copy2(syscall_eax, hidden_eax)

    hidden_crash = hidden / ("artifact_" + os.urandom(8).hex())
    shutil.copy2(crash, hidden_crash)

    hidden_32 = hidden / ("artifact_" + os.urandom(8).hex())
    shutil.copy2(elf32, hidden_32)

    malformed = hidden / ("artifact_" + os.urandom(8).hex())
    malformed.write_bytes(b"not an ELF executable\n" + os.urandom(37))
    malformed.chmod(0o755)

    wrong_machine = hidden / ("artifact_" + os.urandom(8).hex())
    shutil.copy2(clean, wrong_machine)
    data = bytearray(wrong_machine.read_bytes())
    assert data[:4] == b"\x7fELF" and data[4] == 2
    struct.pack_into("<H", data, 18, 183)  # AArch64 rather than x86-64
    wrong_machine.write_bytes(data)
    wrong_machine.chmod(0o755)

    missing = hidden / ("missing_" + os.urandom(8).hex())
    return hidden_clean, [hidden_slow, hidden_rax, hidden_eax, hidden_crash, hidden_32, malformed, wrong_machine, missing]


HIDDEN_CLEAN, HIDDEN_EVIL = prepare_artifacts()


def group_members(pgid):
    members = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / "stat").read_text()
            rest = stat[stat.rfind(")") + 2:].split()
            if int(rest[2]) == pgid:
                members.append(int(entry.name))
        except (OSError, ValueError, IndexError):
            pass
    return members


def invoke_classifier(path, timeout=20):
    proc = subprocess.Popen(
        ["python3", CLASSIFIER_SCRIPT, str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    timed_out = False
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = proc.communicate()

    time.sleep(0.3)
    leaked = group_members(proc.pid)
    if leaked:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return proc.returncode, timed_out, leaked, stdout, stderr


def test_classifier_exists():
    assert os.path.isfile(CLASSIFIER_SCRIPT), f"Classifier script not found at {CLASSIFIER_SCRIPT}"
    assert Path(CLASSIFIER_SCRIPT).read_bytes() != Path("/app/reference_plugin").read_bytes(), "Classifier must not be the reference binary"


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"
    clean_files = sorted([f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))])
    assert len(clean_files) > 0, "No clean files found in corpus."

    failed_files = []
    for fname in clean_files:
        fpath = os.path.join(CLEAN_DIR, fname)
        rc, timed_out, leaked, _, _ = invoke_classifier(fpath)
        if rc != 0 or timed_out or leaked:
            failed_files.append(fname)

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean modified/rejected (expected exit 0). "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"
    evil_files = sorted([f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))])
    assert len(evil_files) > 0, "No evil files found in corpus."

    failed_files = []
    for fname in evil_files:
        fpath = os.path.join(EVIL_DIR, fname)
        rc, timed_out, leaked, _, _ = invoke_classifier(fpath)
        if rc == 0 or timed_out or leaked:
            failed_files.append(fname)

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil bypassed (expected exit > 0). "
            f"Offending files: {', '.join(failed_files)}"
        )


def test_randomized_functional_plugin_is_accepted_and_cleaned_up():
    data = HIDDEN_CLEAN.read_bytes()
    assert data[:5] == b"\x7fELF\x02"
    rc, timed_out, leaked, stdout, stderr = invoke_classifier(HIDDEN_CLEAN)
    assert not timed_out, "Classifier timed out on a functional plugin"
    assert not leaked, f"Classifier left child processes running: {leaked}"
    assert rc == 0, f"Functional randomized plugin rejected; stdout={stdout!r}, stderr={stderr!r}"


@pytest.mark.parametrize("artifact", HIDDEN_EVIL, ids=lambda p: p.name)
def test_randomized_malformed_malicious_and_unreliable_artifacts_are_rejected(artifact):
    rc, timed_out, leaked, stdout, stderr = invoke_classifier(artifact)
    assert not timed_out, f"Classifier timed out instead of rejecting {artifact}"
    assert not leaked, f"Classifier left child processes running for {artifact}: {leaked}"
    assert rc != 0, f"Randomized evil artifact accepted: {artifact}; stdout={stdout!r}, stderr={stderr!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
