#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shlex
import shutil
import stat
import subprocess
import tempfile
import time

import pytest

BASE = "/home/user/math_pipeline"


def run_factorial(exe_file, n):
    result = subprocess.run(
        [exe_file], input=f"{n}\n", capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, (
        f"factorial executable failed for {n}: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    expected = f"{math.factorial(n)}\n"
    assert result.stdout == expected, (
        f"Incorrect result for {n}!. Expected {expected!r}, got {result.stdout!r}"
    )


def test_test_result_log():
    """Check if test_result.log contains the correct factorial of 20."""
    log_path = os.path.join(BASE, "test_result.log")
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "2432902008176640000", (
        f"Expected '2432902008176640000' in {log_path}, got '{content}'"
    )


def test_fix_patch():
    """Check if fix.patch exists and correctly patches the original code."""
    patch_path = os.path.join(BASE, "fix.patch")
    fixed_source = os.path.join(BASE, "factorial.c")
    assert os.path.isfile(patch_path), f"{patch_path} does not exist."
    assert os.path.isfile(fixed_source), f"{fixed_source} does not exist."

    original_code = """#include <stdio.h>
#include <stdlib.h>

int main() {
    int n;
    if (scanf("%d", &n) != 1) return 1;

    int result = 1;
    for (int i = 1; i <= n; i++) {
        result *= i;
    }

    printf("%d\\n", result);
    return 0;
}
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        orig_file = os.path.join(tmpdir, "factorial.c")
        with open(orig_file, "w") as f:
            f.write(original_code)

        patch_cmd = ["patch", orig_file, patch_path]
        result = subprocess.run(patch_cmd, capture_output=True, text=True)
        assert result.returncode == 0, (
            f"Failed to apply patch: {result.stderr}\n{result.stdout}"
        )

        with open(orig_file, "rb") as f:
            patched_bytes = f.read()
        with open(fixed_source, "rb") as f:
            submitted_bytes = f.read()
        assert patched_bytes == submitted_bytes, (
            "Applying fix.patch to the supplied original does not reproduce factorial.c"
        )

        exe_file = os.path.join(tmpdir, "factorial")
        comp_result = subprocess.run(
            ["gcc", orig_file, "-o", exe_file], capture_output=True, text=True
        )
        assert comp_result.returncode == 0, (
            f"Failed to compile patched code: {comp_result.stderr}"
        )

        # Preserve the original edge and upper-bound assertions.
        run_factorial(exe_file, 0)
        run_factorial(exe_file, 20)

        # Exercise unpredictable values and derive their answers independently.
        candidates = list(range(1, 20))
        chosen = []
        while candidates and len(chosen) < 7:
            idx = secrets.randbelow(len(candidates))
            chosen.append(candidates.pop(idx))
        for n in chosen:
            run_factorial(exe_file, n)


def test_submitted_factorial_source():
    """Compile and dynamically exercise the submitted factorial.c itself."""
    source = os.path.join(BASE, "factorial.c")
    assert os.path.isfile(source), f"{source} does not exist."
    with tempfile.TemporaryDirectory() as tmpdir:
        exe = os.path.join(tmpdir, "factorial")
        result = subprocess.run(
            ["gcc", source, "-o", exe], capture_output=True, text=True
        )
        assert result.returncode == 0, f"factorial.c failed to compile: {result.stderr}"
        values = [0, 20]
        pool = list(range(1, 20))
        while pool and len(values) < 9:
            values.append(pool.pop(secrets.randbelow(len(pool))))
        for n in values:
            run_factorial(exe, n)


def configured_path(content, directive):
    match = re.search(
        rf"(?m)^\s*{re.escape(directive)}\s+['\"]?([^\s;'\"]+)", content
    )
    assert match, f"Missing '{directive}' path in proxy.conf"
    path = match.group(1)
    if not os.path.isabs(path):
        path = os.path.join(BASE, path)
    resolved = os.path.realpath(path)
    assert resolved == BASE or resolved.startswith(BASE + os.sep), (
        f"{directive} must write inside {BASE}, got {path}"
    )
    return resolved


def test_proxy_conf():
    """Check if proxy.conf configures the requested stream proxy and local files."""
    conf_path = os.path.join(BASE, "proxy.conf")
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    assert re.search(r"stream\s*\{", content), "Missing 'stream' block in proxy.conf"
    assert re.search(r"listen\s+9090\s*;", content), "Missing 'listen 9090;' in proxy.conf"
    assert re.search(r"proxy_pass\s+(127\.0\.0\.1|localhost):8080\s*;", content), (
        "Missing 'proxy_pass 127.0.0.1:8080;' in proxy.conf"
    )
    configured_path(content, "pid")
    configured_path(content, "access_log")
    configured_path(content, "error_log")


def make_wrapper(path, body):
    with open(path, "w") as f:
        f.write("#!/bin/bash\nset +e\n" + body)
    os.chmod(path, 0o755)


def test_ci_sh():
    """Run ci.sh with a runtime challenge and verify the result traverses the proxy."""
    script_path = os.path.join(BASE, "ci.sh")
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable."

    source_path = os.path.join(BASE, "factorial.c")
    binary_path = os.path.join(BASE, "factorial")
    log_path = os.path.join(BASE, "test_result.log")
    conf_path = os.path.join(BASE, "proxy.conf")

    with open(source_path, "rb") as f:
        saved_source = f.read()
    saved_binary = None
    saved_binary_mode = None
    if os.path.exists(binary_path):
        with open(binary_path, "rb") as f:
            saved_binary = f.read()
        saved_binary_mode = stat.S_IMODE(os.stat(binary_path).st_mode)
    saved_log = None
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            saved_log = f.read()

    with open(conf_path, "r") as f:
        conf_content = f.read()
    access_path = configured_path(conf_content, "access_log")
    saved_access = None
    if os.path.exists(access_path):
        with open(access_path, "rb") as f:
            saved_access = f.read()

    nonce = str(700000000000000000 + secrets.randbelow(200000000000000000))
    probe_source = f'''#include <stdio.h>
int main(void) {{
    int n;
    if (scanf("%d", &n) != 1) return 1;
    if (n == 20) printf("{nonce}\\n");
    else printf("0\\n");
    return 0;
}}
'''

    result = None
    timed_out = False
    observed_log = None
    observed_access = b""

    with tempfile.TemporaryDirectory() as tmpdir:
        marker_dir = os.path.join(tmpdir, "markers")
        wrapper_dir = os.path.join(tmpdir, "bin")
        os.mkdir(marker_dir)
        os.mkdir(wrapper_dir)

        real_gcc = shutil.which("gcc")
        real_socat = shutil.which("socat")
        real_nginx = shutil.which("nginx")
        real_nc = shutil.which("nc")
        real_netcat = shutil.which("netcat")
        assert real_gcc and real_socat and real_nginx, "Required system tools are missing"

        def quoted(value):
            return shlex.quote(value)

        make_wrapper(
            os.path.join(wrapper_dir, "gcc"),
            f'''printf '%q ' "$@" >> {quoted(os.path.join(marker_dir, "gcc.args"))}
printf '\\n' >> {quoted(os.path.join(marker_dir, "gcc.args"))}
exec {quoted(real_gcc)} "$@"
''')
        make_wrapper(
            os.path.join(wrapper_dir, "nginx"),
            f'''printf '%q ' "$@" >> {quoted(os.path.join(marker_dir, "nginx.args"))}
printf '\\n' >> {quoted(os.path.join(marker_dir, "nginx.args"))}
exec {quoted(real_nginx)} "$@"
''')
        make_wrapper(
            os.path.join(wrapper_dir, "socat"),
            f'''printf '%q ' "$@" >> {quoted(os.path.join(marker_dir, "socat.args"))}
printf '\\n' >> {quoted(os.path.join(marker_dir, "socat.args"))}
client=0
for arg in "$@"; do
  [[ "$arg" == *9090* ]] && client=1
done
if [[ "$client" -eq 1 ]]; then
  in_file=$(mktemp)
  out_file=$(mktemp)
  cat > "$in_file"
  {quoted(real_socat)} "$@" < "$in_file" > "$out_file"
  rc=$?
  cat "$out_file" | tee -a {quoted(os.path.join(marker_dir, "network.out"))}
  rm -f "$in_file" "$out_file"
  exit "$rc"
fi
exec {quoted(real_socat)} "$@"
''')

        def install_client_wrapper(name, real_path):
            if not real_path:
                return
            make_wrapper(
                os.path.join(wrapper_dir, name),
                f'''printf '%q ' "$@" >> {quoted(os.path.join(marker_dir, "client.args"))}
printf '\\n' >> {quoted(os.path.join(marker_dir, "client.args"))}
in_file=$(mktemp)
out_file=$(mktemp)
cat > "$in_file"
{quoted(real_path)} "$@" < "$in_file" > "$out_file"
rc=$?
cat "$out_file" | tee -a {quoted(os.path.join(marker_dir, "network.out"))}
rm -f "$in_file" "$out_file"
exit "$rc"
''')

        install_client_wrapper("nc", real_nc)
        install_client_wrapper("netcat", real_netcat)

        try:
            with open(source_path, "w") as f:
                f.write(probe_source)
            if os.path.exists(log_path):
                os.remove(log_path)
            if os.path.exists(access_path):
                os.remove(access_path)

            env = os.environ.copy()
            env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
            try:
                result = subprocess.run(
                    [script_path], cwd=BASE, env=env,
                    capture_output=True, text=True, timeout=15
                )
            except subprocess.TimeoutExpired:
                timed_out = True

            if os.path.isfile(log_path):
                with open(log_path, "r") as f:
                    observed_log = f.read()
            if os.path.isfile(access_path):
                with open(access_path, "rb") as f:
                    observed_access = f.read()

            def read_marker(name):
                path = os.path.join(marker_dir, name)
                if not os.path.isfile(path):
                    return ""
                with open(path, "r", errors="replace") as f:
                    return f.read()

            gcc_args = read_marker("gcc.args")
            socat_args = read_marker("socat.args")
            nginx_args = read_marker("nginx.args")
            client_args = read_marker("client.args")
            network_output = read_marker("network.out")
        finally:
            subprocess.run(["pkill", "-TERM", "-x", "nginx"], capture_output=True)
            subprocess.run(["pkill", "-TERM", "-x", "socat"], capture_output=True)
            time.sleep(0.3)
            subprocess.run(["pkill", "-KILL", "-x", "nginx"], capture_output=True)
            subprocess.run(["pkill", "-KILL", "-x", "socat"], capture_output=True)

            with open(source_path, "wb") as f:
                f.write(saved_source)
            if saved_binary is None:
                if os.path.exists(binary_path):
                    os.remove(binary_path)
            else:
                with open(binary_path, "wb") as f:
                    f.write(saved_binary)
                os.chmod(binary_path, saved_binary_mode)
            if saved_log is None:
                if os.path.exists(log_path):
                    os.remove(log_path)
            else:
                with open(log_path, "wb") as f:
                    f.write(saved_log)
            if saved_access is None:
                if os.path.exists(access_path):
                    os.remove(access_path)
            else:
                os.makedirs(os.path.dirname(access_path), exist_ok=True)
                with open(access_path, "wb") as f:
                    f.write(saved_access)

        assert not timed_out, "ci.sh timed out and did not shut down its services"
        assert result is not None and result.returncode == 0, (
            f"ci.sh failed with return code {getattr(result, 'returncode', None)}.\n"
            f"Stdout: {getattr(result, 'stdout', '')}\n"
            f"Stderr: {getattr(result, 'stderr', '')}"
        )
        assert observed_log == nonce + "\n", (
            "ci.sh did not write the output produced by the runtime-challenged service; "
            f"expected {nonce!r}, got {observed_log!r}"
        )
        assert "factorial.c" in gcc_args and "factorial" in gcc_args, (
            "ci.sh did not compile factorial.c into factorial"
        )
        assert "8080" in socat_args and "factorial" in socat_args, (
            "ci.sh did not start socat on port 8080 executing factorial"
        )
        assert "proxy.conf" in nginx_args, (
            "ci.sh did not start Nginx using proxy.conf"
        )

        client_used_9090 = "9090" in client_args or "9090" in socat_args
        captured_nonce = nonce in network_output.splitlines()
        access_recorded = bool(observed_access.strip())
        assert (client_used_9090 and captured_nonce) or access_recorded, (
            "No evidence that ci.sh obtained the challenged result through Nginx port 9090"
        )

    socat_res = subprocess.run(["pgrep", "-x", "socat"], capture_output=True)
    assert socat_res.returncode != 0, "Lingering socat process found."
    nginx_res = subprocess.run(["pgrep", "-x", "nginx"], capture_output=True)
    assert nginx_res.returncode != 0, "Lingering nginx process found."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
