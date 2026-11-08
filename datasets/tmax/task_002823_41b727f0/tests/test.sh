#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import shutil
import subprocess


def test_libprocessor_so_exists():
    so_path = "/home/user/native_module/libprocessor.so"
    assert os.path.isfile(so_path), f"The shared library {so_path} was not created."

    with open(so_path, "rb") as f:
        header = f.read(4)
        assert header == b"\x7fELF", f"{so_path} is not a valid ELF file."


def test_process_manifest_script_exists():
    script_path = "/home/user/process_manifest.py"
    assert os.path.isfile(script_path), f"The script {script_path} was not created."


def test_outputs_file_content():
    output_path = "/home/user/outputs.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."

    with open(output_path, "r") as f:
        content = f.read().splitlines()

    expected_content = [
        "abc",
        "xyz",
        "helo",
        "build_enginer",
        "consecutive",
        "0",
    ]
    assert content == expected_content, (
        f"The contents of {output_path} do not match the expected output. Got: {content}"
    )


def test_makefile_rebuilds_and_library_manages_allocations():
    module = "/home/user/native_module"
    so_path = os.path.join(module, "libprocessor.so")
    obj_path = os.path.join(module, "processor.o")

    for path in (so_path, obj_path):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ["make", "-C", module], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}"
    assert os.path.isfile(so_path), "make did not create libprocessor.so"
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    lib = ctypes.CDLL(so_path)
    lib.process_string.argtypes = [ctypes.c_char_p]
    lib.process_string.restype = ctypes.c_void_p
    lib.free_string.argtypes = [ctypes.c_void_p]
    lib.free_string.restype = None
    lib.get_active_allocations.argtypes = []
    lib.get_active_allocations.restype = ctypes.c_int

    baseline = lib.get_active_allocations()
    assert baseline == 0
    ptr = lib.process_string(b"aaabccccddeee")
    assert ptr, "process_string returned NULL"
    assert lib.get_active_allocations() == baseline + 1
    assert ctypes.string_at(ptr) == b"abcde"
    lib.free_string(ptr)
    assert lib.get_active_allocations() == baseline


def test_script_executes_ffi_and_frees_every_result(tmp_path):
    input_path = "/home/user/inputs.txt"
    output_path = "/home/user/outputs.txt"
    script_path = "/home/user/process_manifest.py"
    so_path = "/home/user/native_module/libprocessor.so"

    input_backup = tmp_path / "inputs.txt"
    output_backup = tmp_path / "outputs.txt"
    so_backup = tmp_path / "libprocessor.so"
    shutil.copy2(input_path, input_backup)
    shutil.copy2(output_path, output_backup)
    shutil.copy2(so_path, so_backup)

    probe_source = tmp_path / "probe.c"
    probe_library = tmp_path / "libprocessor.so"
    probe_log = tmp_path / ("ffi-" + secrets.token_hex(12) + ".log")
    probe_source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int active_allocations = 0;

static void record_event(char event) {
    const char *path = getenv("PROCESSOR_PROBE_LOG");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (f) {
        fputc(event, f);
        fputc('\n', f);
        fclose(f);
    }
}

int get_active_allocations(void) {
    record_event('G');
    return active_allocations;
}

char *process_string(const char *input) {
    record_event('P');
    if (!input) return NULL;
    size_t len = strlen(input);
    char *output = malloc(len + 1);
    if (!output) return NULL;
    active_allocations++;
    size_t j = 0;
    char last = '\0';
    for (size_t i = 0; i < len; i++) {
        if (input[i] != last) {
            output[j++] = input[i];
            last = input[i];
        }
    }
    output[j] = '\0';
    return output;
}

void free_string(char *ptr) {
    record_event('F');
    if (ptr) {
        free(ptr);
        active_allocations--;
    }
}
''')

    build = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(probe_library), str(probe_source)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert build.returncode == 0, f"Could not build verifier probe library:\n{build.stdout}"

    token = secrets.token_hex(10)
    cases = [
        "aa" + token + "bbb",
        token[0] * 5 + "_manifest__" + token[1] * 4,
        "xxxyzzzzzzq",
        "buildddd_eeengineerrr_" + token,
        "1122333332211",
        token + token[-1] * 3,
        "no_duplicates_" + token,
    ]

    def normalize(value):
        result = []
        for char in value:
            if not result or result[-1] != char:
                result.append(char)
        return "".join(result)

    try:
        shutil.copy2(probe_library, so_path)
        with open(input_path, "w", encoding="utf-8", newline="") as f:
            for value in cases:
                f.write(value + "\n")

        env = os.environ.copy()
        env["PROCESSOR_PROBE_LOG"] = str(probe_log)
        run = subprocess.run(
            ["python3", script_path], cwd="/home/user", env=env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
        )
        assert run.returncode == 0, f"process_manifest.py failed:\n{run.stdout}"
        assert os.path.isfile(output_path), "The script did not create outputs.txt"

        with open(output_path, encoding="utf-8") as f:
            actual = f.read().splitlines()
        expected = [normalize(value) for value in cases] + ["0"]
        assert actual == expected, f"Script output for verifier inputs was {actual}, expected {expected}"

        assert probe_log.is_file(), "The script did not call the loaded C library"
        events = probe_log.read_text().splitlines()
        assert events.count("P") == len(cases), "process_string was not called once per input"
        assert events.count("F") == len(cases), "free_string was not called once per returned pointer"
        assert events.count("G") >= 1, "get_active_allocations was not called"
        assert events[-1] == "G", "Allocation count was not checked after processing and freeing"
    finally:
        shutil.copy2(input_backup, input_path)
        shutil.copy2(output_backup, output_path)
        shutil.copy2(so_backup, so_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
