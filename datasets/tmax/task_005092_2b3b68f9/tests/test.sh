#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

SERVICE_DIR = "/home/user/service"
REPORT_PATH = "/home/user/debug_report.txt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=60, **kwargs)


def library_signature():
    result = run(["nm", "-D", "--defined-only", "--demangle", os.path.join(SERVICE_DIR, "libprocessor.so")])
    assert result.returncode == 0, result.stderr
    matches = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3 and parts[2].startswith("process_record("):
            matches.append(parts[2])
    assert len(matches) == 1, f"Expected exactly one exported process_record function, found: {matches}"
    return matches[0]


def normalize_signature(signature):
    signature = signature.strip()
    if signature.startswith("void "):
        signature = signature[5:]
    signature = re.sub(r"\s+", " ", signature)
    signature = signature.replace("const double*", "double const*")
    return signature


def valgrind_definite_leak(executable, log_path):
    result = run([
        "valgrind", "--leak-check=full", "--show-leak-kinds=all",
        f"--log-file={log_path}", executable
    ], cwd=SERVICE_DIR)
    assert result.returncode == 0, f"{executable} failed under valgrind:\n{result.stdout}\n{result.stderr}"
    with open(log_path, "r") as f:
        output = f.read()
    match = re.search(r"definitely lost:\s*([\d,]+) bytes in ([\d,]+) blocks", output)
    assert match, f"Could not find the definite-leak summary in valgrind output:\n{output}"
    return int(match.group(1).replace(",", "")), int(match.group(2).replace(",", ""))


def test_debug_report_exists():
    assert os.path.exists(REPORT_PATH), f"The debug report was not found at {REPORT_PATH}."
    assert os.path.isfile(REPORT_PATH), f"The path {REPORT_PATH} is not a regular file."


def test_debug_report_content():
    with open(REPORT_PATH, "r") as f:
        raw = f.read()
    lines = [line.strip() for line in raw.strip().splitlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {REPORT_PATH}, but found {len(lines)}."
    assert len(raw.splitlines()) == 2, "The report must contain exactly two lines and no blank lines."

    signature_line = lines[0]
    leak_line = lines[1]

    # Retain the original signature assertions.
    assert "process_record" in signature_line, "The function name 'process_record' is missing from the signature line."
    assert "double" in signature_line, "The type 'double' is missing from the signature line."
    assert "const" in signature_line, "The 'const' qualifier is missing from the signature line."
    assert "int" in signature_line, "The type 'int' is missing from the signature line."

    # Require an actual, complete demangled signature from the supplied library.
    expected_signature = library_signature()
    assert normalize_signature(signature_line) == normalize_signature(expected_signature), \
        f"Expected the demangled signature '{expected_signature}', got '{signature_line}'."

    # Retain the original exact leak assertion.
    assert leak_line == "1024", f"Expected the memory leak to be exactly '1024' bytes, but got '{leak_line}'."


def test_sources_build_link_and_exercise_library():
    header = os.path.join(SERVICE_DIR, "processor.h")
    source = os.path.join(SERVICE_DIR, "service.cpp")
    library = os.path.join(SERVICE_DIR, "libprocessor.so")
    assert os.path.isfile(header), "processor.h is missing or is not a regular file."
    assert os.path.isfile(source), "service.cpp is missing or is not a regular file."
    assert os.path.isfile(library), "libprocessor.so is missing or is not a regular file."

    expected_signature = library_signature()

    # A const-input MRE ensures processor.h exposes the corrected declaration.
    probe_source = "/tmp/processor_probe.cpp"
    probe_object = "/tmp/processor_probe.o"
    probe_binary = "/tmp/processor_probe"
    with open(probe_source, "w") as f:
        f.write('#include "/home/user/service/processor.h"\n'
                'int main() { const double data[1] = {1.0}; process_record(data, 1); return 0; }\n')

    result = run(["g++", "-c", probe_source, "-o", probe_object])
    assert result.returncode == 0, f"processor.h does not compile with const input:\n{result.stderr}"
    undefined = run(["nm", "-u", "--demangle", probe_object])
    assert undefined.returncode == 0, undefined.stderr
    assert expected_signature in undefined.stdout, \
        f"The header probe does not reference the library signature {expected_signature}."

    result = run([
        "g++", probe_source, "-o", probe_binary, "-L.", "-lprocessor", "-Wl,-rpath=."
    ], cwd=SERVICE_DIR)
    assert result.returncode == 0, f"The header MRE failed to link:\n{result.stderr}"

    probe_bytes, probe_blocks = valgrind_definite_leak(probe_binary, "/tmp/probe-valgrind.log")
    assert probe_bytes == 1024 and probe_blocks == 1, \
        f"One direct process_record call leaked {probe_bytes} bytes in {probe_blocks} blocks, not 1024 bytes in one block."

    # Compile service.cpp separately so it must reference the corrected external symbol.
    service_object = "/tmp/service.o"
    result = run(["g++", "-c", "service.cpp", "-o", service_object], cwd=SERVICE_DIR)
    assert result.returncode == 0, f"service.cpp failed to compile:\n{result.stderr}"
    undefined = run(["nm", "-u", "--demangle", service_object])
    assert undefined.returncode == 0, undefined.stderr
    assert expected_signature in undefined.stdout, \
        f"service.cpp does not reference the library signature {expected_signature}."

    service_binary = os.path.join(SERVICE_DIR, "service")
    if os.path.lexists(service_binary):
        os.remove(service_binary)
    result = run([
        "g++", "service.cpp", "-o", "service", "-L.", "-lprocessor", "-Wl,-rpath=."
    ], cwd=SERVICE_DIR)
    assert result.returncode == 0, f"The required service build/link command failed:\n{result.stderr}"
    assert os.path.isfile(service_binary) and os.access(service_binary, os.X_OK), \
        "The build did not produce an executable service binary."

    service_bytes, service_blocks = valgrind_definite_leak(service_binary, "/tmp/service-valgrind.log")
    assert service_bytes == 1024 and service_blocks == 1, \
        f"The service leaked {service_bytes} bytes in {service_blocks} blocks; expected one 1024-byte leak."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
