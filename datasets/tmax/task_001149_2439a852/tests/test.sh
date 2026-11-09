#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import re
import secrets
import subprocess
import tempfile


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 10)
    return subprocess.run(cmd, **kwargs)


def test_deployment_structure():
    current_symlink = "/home/user/opt/edge_sensor/current"
    v2_release_dir = "/home/user/opt/edge_sensor/releases/v2"

    assert os.path.islink(current_symlink), f"{current_symlink} is not a symlink"
    target = os.readlink(current_symlink)
    assert target == v2_release_dir, f"Symlink {current_symlink} points to {target}, expected {v2_release_dir}"

    sensor_filter_path = os.path.join(current_symlink, "sensor_filter")
    libcjson_path = os.path.join(current_symlink, "libcjson.so")

    assert os.path.isfile(sensor_filter_path), f"Missing sensor_filter binary at {sensor_filter_path}"
    assert os.access(sensor_filter_path, os.X_OK), f"sensor_filter at {sensor_filter_path} is not executable"
    assert os.path.isfile(libcjson_path), f"Missing libcjson.so at {libcjson_path}"


def test_backup_logic():
    backup_dummy = "/home/user/opt/edge_sensor/backup/dummy_binary"
    assert os.path.isfile(backup_dummy), f"Backup logic failed: missing {backup_dummy}"


def test_sensor_filter_clean_corpus():
    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert len(clean_files) > 0, "No files found in clean corpus"

    executable = "/home/user/opt/edge_sensor/current/sensor_filter"
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/opt/edge_sensor/current"

    failed_files = []
    for path in clean_files:
        result = run([executable, path], env=env)
        if result.returncode != 0:
            failed_files.append(os.path.basename(path))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_files)}"


def test_sensor_filter_evil_corpus():
    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(evil_files) > 0, "No files found in evil corpus"

    executable = "/home/user/opt/edge_sensor/current/sensor_filter"
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/opt/edge_sensor/current"

    failed_files = []
    for path in evil_files:
        result = run([executable, path], env=env)
        if result.returncode != 1:
            failed_files.append(os.path.basename(path))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed: {', '.join(failed_files)}"


def test_build_artifacts_and_sources():
    source = "/home/user/sensor_filter.c"
    home_binary = "/home/user/sensor_filter"
    deployed_binary = "/home/user/opt/edge_sensor/current/sensor_filter"
    built_library = "/app/cJSON-1.7.15/libcjson.so"
    deployed_library = "/home/user/opt/edge_sensor/current/libcjson.so"
    makefile = "/app/cJSON-1.7.15/Makefile"
    deploy_script = "/home/user/deploy.sh"

    assert os.path.isfile(source), f"Missing C source at {source}"
    assert os.path.isfile(home_binary) and os.access(home_binary, os.X_OK), f"Missing executable at {home_binary}"
    assert os.path.isfile(built_library), f"make did not produce {built_library}"
    assert os.path.isfile(deploy_script), f"Missing deployment script at {deploy_script}"
    assert run(["bash", "-n", deploy_script]).returncode == 0, "deploy.sh has invalid bash syntax"

    source_text = open(source, encoding="utf-8", errors="replace").read()
    assert re.search(r"\bcJSON_Parse\s*\(", source_text), "sensor_filter.c does not call cJSON_Parse"

    make_text = open(makefile, encoding="utf-8", errors="replace").read()
    assert "arm-linux-gnueabihf-gcc" not in make_text, "The cross-compiler remains in the Makefile"
    assert re.search(r"(?m)^\s*CC\s*[:?]?=\s*gcc(?:\s|$)", make_text), "Makefile does not select gcc"

    for artifact in (home_binary, deployed_binary, built_library, deployed_library):
        header = run(["readelf", "-h", artifact], text=True)
        assert header.returncode == 0, f"{artifact} is not an ELF artifact"
        assert "Advanced Micro Devices X86-64" in header.stdout, f"{artifact} was not built for x86_64"

    dynamic = run(["readelf", "-d", deployed_binary], text=True)
    assert dynamic.returncode == 0
    assert re.search(r"NEEDED.*libcjson\.so", dynamic.stdout), "sensor_filter is not dynamically linked to libcjson"

    binary_symbols = run(["nm", "-D", deployed_binary], text=True)
    assert binary_symbols.returncode == 0
    assert re.search(r"\bU\s+cJSON_Parse(?:@\S+)?\s*$", binary_symbols.stdout, re.MULTILINE), "sensor_filter has no dynamic cJSON_Parse reference"

    library_symbols = run(["nm", "-D", deployed_library], text=True)
    assert library_symbols.returncode == 0
    assert re.search(r"\b[TW]\s+cJSON_Parse\s*$", library_symbols.stdout, re.MULTILINE), "deployed libcjson.so does not export cJSON_Parse"

    def digest(path):
        with open(path, "rb") as stream:
            return hashlib.sha256(stream.read()).digest()

    assert digest(home_binary) == digest(deployed_binary), "The built sensor_filter was not copied into the release"
    assert digest(built_library) == digest(deployed_library), "The built libcjson.so was not copied into the release"


def test_novel_payloads_and_argument_handling():
    executable = "/home/user/opt/edge_sensor/current/sensor_filter"
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/opt/edge_sensor/current"

    with tempfile.TemporaryDirectory(prefix="sensor-check-" + secrets.token_hex(8) + "-") as directory:
        nonce = secrets.token_hex(6)
        cases = [
            (f'{{"sensor_id":"","value":0,"extra":"{nonce}"}}', 0),
            (f'{{"value":-17.25,"sensor_id":"unit-{nonce}"}}', 0),
            ('  {"sensor_id":"' + ('x' * 31) + '","value":6.02e23}\n', 0),
            ('{"sensor_id":"' + ('y' * 32) + '","value":1}', 1),
            ('{"sensor_id":12,"value":1}', 1),
            ('{"sensor_id":"ok","value":false}', 1),
            ('{"sensor_id":"ok","value":null}', 1),
            ('{"sensor_id":"ok","value":[1]}', 1),
            ('{"sensor_id":"ok"}', 1),
            ('{"value":3}', 1),
            ('[ {"sensor_id":"ok","value":3} ]', 1),
            ('"not an object"', 1),
            ('{"sensor_id":"ok","value":1,}', 1),
            ('{"sensor_id":"ok","value":', 1),
            ('this is not json', 1),
        ]

        for index, (payload, expected) in enumerate(cases):
            path = os.path.join(directory, secrets.token_hex(10) + f"-{index}.dat")
            with open(path, "w", encoding="utf-8") as stream:
                stream.write(payload)
            result = run([executable, path], env=env)
            assert result.returncode == expected, f"Novel case {index} returned {result.returncode}, expected {expected}"

        missing = os.path.join(directory, secrets.token_hex(12) + ".missing")
        assert run([executable, missing], env=env).returncode == 1, "A missing input file was not rejected"
        assert run([executable], env=env).returncode == 1, "Invocation without an argument was not rejected"
        assert run([executable, missing, missing], env=env).returncode == 1, "Invocation with extra arguments was not rejected"


def test_cjson_parse_is_exercised_at_runtime():
    executable = "/home/user/opt/edge_sensor/current/sensor_filter"
    with tempfile.TemporaryDirectory(prefix="cjson-hook-") as directory:
        shim_source = os.path.join(directory, "shim.c")
        shim_library = os.path.join(directory, "shim.so")
        marker = os.path.join(directory, "called")
        payload = os.path.join(directory, secrets.token_hex(8) + ".json")

        with open(payload, "w", encoding="utf-8") as stream:
            stream.write('{"sensor_id":"runtime-check","value":42}')
        with open(shim_source, "w", encoding="utf-8") as stream:
            stream.write(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
void *cJSON_Parse(const char *value) {
    typedef void *(*parse_fn)(const char *);
    static parse_fn real_parse;
    const char *marker = getenv("CJSON_CALL_MARKER");
    if (marker) {
        int fd = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) { write(fd, "1", 1); close(fd); }
    }
    if (!real_parse) real_parse = (parse_fn)dlsym(RTLD_NEXT, "cJSON_Parse");
    return real_parse ? real_parse(value) : 0;
}
''')

        compiled = run(["gcc", "-shared", "-fPIC", shim_source, "-o", shim_library, "-ldl"], text=True)
        assert compiled.returncode == 0, f"Failed to build cJSON runtime hook: {compiled.stderr}"

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = "/home/user/opt/edge_sensor/current"
        env["LD_PRELOAD"] = shim_library
        env["CJSON_CALL_MARKER"] = marker
        result = run([executable, payload], env=env)
        assert result.returncode == 0, "Valid runtime-hook payload was rejected"
        assert os.path.isfile(marker) and os.path.getsize(marker) > 0, "sensor_filter did not invoke cJSON_Parse at runtime"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
