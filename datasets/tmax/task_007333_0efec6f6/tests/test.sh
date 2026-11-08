#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import uuid


def get_expected_iface():
    with open('/proc/net/route', 'r') as f:
        for line in f:
            parts = line.split()
            if len(parts) > 1 and parts[1] == "00000000":
                return parts[0]
    return ""


def test_gateway_finder_executable():
    bin_path = "/home/user/bin/gateway_finder"
    assert os.path.isfile(bin_path), f"Executable {bin_path} does not exist."
    st = os.stat(bin_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not a compiled ELF executable."


def test_gateway_finder_source_exists_and_compiles():
    source_path = "/home/user/src/gateway_finder.c"
    assert os.path.isfile(source_path), f"C source {source_path} does not exist."

    result = subprocess.run(
        ["gcc", "-std=c11", source_path, "-o", "/tmp/gateway_finder_from_source"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"C source did not compile:\n{result.stderr}"
    assert os.path.isfile("/tmp/gateway_finder_from_source")


def test_run_finder_script():
    script_path = "/home/user/run_finder.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."


def test_wrapper_exports_variable_and_invokes_binary():
    script_path = "/home/user/run_finder.sh"
    bin_path = "/home/user/bin/gateway_finder"
    backup_path = "/home/user/bin/.gateway_finder.verifier_backup"
    record_path = f"/tmp/wrapper_probe_{uuid.uuid4().hex}"
    output_dir = "/home/user/output"
    output_path = "/home/user/output/iface.log"

    if os.path.exists(backup_path):
        os.remove(backup_path)
    os.replace(bin_path, backup_path)
    try:
        with open(bin_path, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("printf '%s\\n' \"$GW_OUT_FILE\" > \"$PROBE_RECORD\"\n")
            f.write("printf 'probe\\n' > \"$GW_OUT_FILE\"\n")
        os.chmod(bin_path, 0o755)

        if os.path.isdir(output_dir):
            shutil.rmtree(output_dir)
        elif os.path.exists(output_dir):
            os.remove(output_dir)

        env = os.environ.copy()
        env["PROBE_RECORD"] = record_path
        env["GW_OUT_FILE"] = "/tmp/wrong_path"
        result = subprocess.run([script_path], env=env, capture_output=True, text=True)
        assert result.returncode == 0, f"Wrapper failed when executed: {result.stderr}"
        assert os.path.isdir(output_dir), "Wrapper did not create /home/user/output."
        assert os.path.isfile(record_path), "Wrapper did not invoke /home/user/bin/gateway_finder."
        with open(record_path) as f:
            exported_path = f.read().strip()
        assert exported_path == output_path, "Wrapper did not export the required GW_OUT_FILE value."
        assert os.path.isfile(output_path), "Invoked binary could not write through exported GW_OUT_FILE."
    finally:
        if os.path.exists(bin_path):
            os.remove(bin_path)
        os.replace(backup_path, bin_path)
        if os.path.exists(record_path):
            os.remove(record_path)

    if os.path.isdir(output_dir):
        shutil.rmtree(output_dir)
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Wrapper failed with the real binary: {result.stderr}"
    assert os.path.isfile(output_path), "Running the wrapper did not generate iface.log."


def test_bash_profile():
    profile_path = "/home/user/.bash_profile"
    assert os.path.isfile(profile_path), f"{profile_path} does not exist."
    with open(profile_path, 'r') as f:
        content = f.read()
    assert "export DEFAULT_GW_CHECK=1" in content, f"{profile_path} does not contain 'export DEFAULT_GW_CHECK=1'."


def test_iface_log_output():
    log_path = "/home/user/output/iface.log"
    assert os.path.isfile(log_path), f"Output file {log_path} does not exist. Did you run the wrapper script?"

    expected_iface = get_expected_iface()
    with open(log_path, 'r') as f:
        actual_iface = f.read().strip()

    assert actual_iface == expected_iface, f"Expected interface '{expected_iface}', but got '{actual_iface}' in {log_path}."


def test_gateway_finder_functionality():
    bin_path = "/home/user/bin/gateway_finder"
    test_log_path = "/home/user/test_iface.log"

    if os.path.exists(test_log_path):
        os.remove(test_log_path)

    env = os.environ.copy()
    env["GW_OUT_FILE"] = test_log_path

    result = subprocess.run([bin_path], env=env, capture_output=True)
    assert result.returncode == 0, f"{bin_path} did not exit cleanly."
    assert os.path.isfile(test_log_path), f"{bin_path} did not create the output file specified by GW_OUT_FILE."

    expected_iface = get_expected_iface()
    with open(test_log_path, 'r') as f:
        actual_iface = f.read().strip()

    assert actual_iface == expected_iface, f"Binary produced '{actual_iface}' instead of '{expected_iface}'."


def build_route_redirector(directory):
    hook_source = os.path.join(directory, "route_redirect.c")
    hook_library = os.path.join(directory, "route_redirect.so")
    with open(hook_source, "w") as f:
        f.write(r'''#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *redirect_path(const char *path) {
    const char *replacement = getenv("GW_TEST_ROUTE");
    if (replacement && path && strcmp(path, "/proc/net/route") == 0)
        return replacement;
    return path;
}

FILE *fopen(const char *path, const char *mode) {
    static FILE *(*real_fopen)(const char *, const char *);
    if (!real_fopen) real_fopen = dlsym(RTLD_NEXT, "fopen");
    return real_fopen(redirect_path(path), mode);
}

FILE *fopen64(const char *path, const char *mode) {
    static FILE *(*real_fopen64)(const char *, const char *);
    if (!real_fopen64) real_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    return real_fopen64(redirect_path(path), mode);
}

int open(const char *path, int flags, ...) {
    static int (*real_open)(const char *, int, ...);
    mode_t mode = 0;
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
        return real_open(redirect_path(path), flags, mode);
    }
    return real_open(redirect_path(path), flags);
}

int open64(const char *path, int flags, ...) {
    static int (*real_open64)(const char *, int, ...);
    mode_t mode = 0;
    if (!real_open64) real_open64 = dlsym(RTLD_NEXT, "open64");
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
        return real_open64(redirect_path(path), flags, mode);
    }
    return real_open64(redirect_path(path), flags);
}
''')
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", hook_source, "-o", hook_library, "-ldl"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Could not build verifier route redirector: {result.stderr}"
    return hook_library


def test_parser_on_unseen_routing_table():
    source_path = "/home/user/src/gateway_finder.c"
    installed_binary = "/home/user/bin/gateway_finder"

    with tempfile.TemporaryDirectory(prefix="gateway_test_") as directory:
        rebuilt_binary = os.path.join(directory, "rebuilt_gateway_finder")
        result = subprocess.run(
            ["gcc", "-std=c11", source_path, "-o", rebuilt_binary],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"C source did not compile: {result.stderr}"

        hook_library = build_route_redirector(directory)
        expected_iface = "gw" + uuid.uuid4().hex[:10]
        route_path = os.path.join(directory, "route")
        with open(route_path, "w") as f:
            f.write("Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\n")
            f.write("ignored0\t00112233\t00000000\t0001\t0\t0\t0\tFFFFFFFF\t0\t0\t0\n")
            f.write(f"{expected_iface}\t00000000\t01020304\t0003\t0\t0\t7\t00000000\t0\t0\t0\n")

        for label, binary in (("installed binary", installed_binary), ("compiled C source", rebuilt_binary)):
            output_path = os.path.join(directory, label.replace(" ", "_") + ".log")
            env = os.environ.copy()
            env["GW_OUT_FILE"] = output_path
            env["GW_TEST_ROUTE"] = route_path
            env["LD_PRELOAD"] = hook_library
            result = subprocess.run([binary], env=env, capture_output=True, text=True)
            assert result.returncode == 0, f"{label} failed on a valid routing table: {result.stderr}"
            assert os.path.isfile(output_path), f"{label} did not write to GW_OUT_FILE."
            with open(output_path, "rb") as f:
                actual = f.read()
            assert actual == (expected_iface + "\n").encode(), \
                f"{label} did not parse the generated default route; got {actual!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
