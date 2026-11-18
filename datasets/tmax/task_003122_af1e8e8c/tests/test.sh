#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess

PROJECT_DIR = "/home/user/project"
URL_TOOL = os.path.join(PROJECT_DIR, "url_tool")
LIB_SO = os.path.join(PROJECT_DIR, "liburlsanitizer.so")
LOG_PATH = os.path.join(PROJECT_DIR, "ci_success.log")


def run(args, cwd=PROJECT_DIR, env=None):
    return subprocess.run(
        args,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        check=True,
        timeout=20,
    )


def clean_artifacts(remove_log=False):
    for name in ("url_tool", "liburlsanitizer.so", "url_sanitizer.o"):
        try:
            os.remove(os.path.join(PROJECT_DIR, name))
        except FileNotFoundError:
            pass
    if remove_log:
        try:
            os.remove(LOG_PATH)
        except FileNotFoundError:
            pass


def assert_artifacts():
    assert os.path.isfile(URL_TOOL), "url_tool binary is missing. Did build.sh succeed?"
    assert os.access(URL_TOOL, os.X_OK), "url_tool is not executable."
    assert os.path.isfile(LIB_SO), "liburlsanitizer.so is missing."

    with open(URL_TOOL, "rb") as f:
        assert f.read(4) == b"\x7fELF", "url_tool is not an ELF executable."
    with open(LIB_SO, "rb") as f:
        assert f.read(4) == b"\x7fELF", "liburlsanitizer.so is not an ELF shared object."

    tool_headers = run(["readelf", "-h", URL_TOOL]).stdout
    lib_headers = run(["readelf", "-h", LIB_SO]).stdout
    assert re.search(r"Type:\s+(?:DYN|EXEC)", tool_headers), "url_tool has an invalid ELF type."
    assert re.search(r"Type:\s+DYN", lib_headers), "liburlsanitizer.so is not a shared object."

    dynamic = run(["readelf", "-d", URL_TOOL]).stdout
    assert re.search(r"Shared library: \[liburlsanitizer\.so\]", dynamic), \
        "url_tool is not dynamically linked to liburlsanitizer.so."

    tool_symbols = run(["nm", "-D", URL_TOOL]).stdout
    lib_symbols = run(["nm", "-D", LIB_SO]).stdout
    assert re.search(r"\bU\s+sanitize_path(?:@\S+)?\s*$", tool_symbols, re.MULTILINE), \
        "url_tool does not import sanitize_path from the shared library."
    assert re.search(r"\b[TB]\s+sanitize_path(?:@\S+)?\s*$", lib_symbols, re.MULTILINE), \
        "liburlsanitizer.so does not export sanitize_path."


def clean_runtime_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("LD_PRELOAD", None)
    return env


def assert_tool_behavior():
    env = clean_runtime_env()
    token = secrets.token_hex(12)
    benign = f"/dynamic/{token}/resource"
    traversal = f"/dynamic/{token}/../private"

    # Execute from outside the project and without loader environment overrides.
    result = run([URL_TOOL, benign], cwd="/tmp", env=env)
    assert result.stdout.strip() == benign, "url_tool did not preserve a normal path."

    result = run([URL_TOOL, traversal], cwd="/tmp", env=env)
    assert result.stdout.strip() == "/SECURE_ROUTING_ERROR", \
        "url_tool did not reject a traversal path."


def assert_routing_behavior():
    script = os.path.join(PROJECT_DIR, "test_routing.sh")
    assert os.path.isfile(script) and os.access(script, os.X_OK), \
        "test_routing.sh is missing or not executable."

    token = secrets.token_hex(10)
    path = f"/routes/{token}/item"
    query = f"session={secrets.token_hex(8)}&next=../private"
    result = run([script, f"https://example.com{path}?{query}"])
    assert result.stdout.strip() == path, \
        f"test_routing.sh failed to strip query parameters: {result.stdout.strip()}"

    bad_path = f"/routes/{token}/../passwd"
    result = run([script, f"http://example.com{bad_path}?token={secrets.token_hex(8)}"])
    assert result.stdout.strip() == "/SECURE_ROUTING_ERROR", \
        "test_routing.sh did not pass the stripped traversal path to the checker."

    # Replace url_tool briefly with a probe, proving that the routing script passes
    # the query-free path to the tool rather than printing a canned answer itself.
    backup = URL_TOOL + ".verifier-backup"
    probe_log = os.path.join(PROJECT_DIR, ".url_tool_probe")
    marker = "PROBE_" + secrets.token_hex(12)
    probe_path = f"/probe/{secrets.token_hex(12)}/value"
    probe_query = f"a={secrets.token_hex(10)}&danger=../x"
    os.replace(URL_TOOL, backup)
    try:
        with open(URL_TOOL, "w") as f:
            f.write("#!/bin/bash\nprintf '%s' \"$1\" > " + repr(probe_log) + "\nprintf '%s\\n' " + repr(marker) + "\n")
        os.chmod(URL_TOOL, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                           stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        result = run([script, f"http://example.com{probe_path}?{probe_query}"])
        assert result.stdout.strip() == marker, "test_routing.sh did not use url_tool's result."
        assert os.path.isfile(probe_log), "test_routing.sh did not invoke ./url_tool."
        with open(probe_log) as f:
            received = f.read()
        assert received == probe_path, \
            f"test_routing.sh passed {received!r}, expected query-free path {probe_path!r}."
    finally:
        try:
            os.remove(URL_TOOL)
        except FileNotFoundError:
            pass
        os.replace(backup, URL_TOOL)
        try:
            os.remove(probe_log)
        except FileNotFoundError:
            pass


def test_complete_task():
    # Preserve the original requirement that the agent left the successful CI log.
    assert os.path.isfile(LOG_PATH), f"File {LOG_PATH} is missing. Did you run ci_run.sh?"
    with open(LOG_PATH) as f:
        assert f.read().strip() == "CI SUCCESS", \
            f"Expected 'CI SUCCESS' in {LOG_PATH}."

    # A clean build must create the real linked artifacts.
    clean_artifacts()
    run(["./build.sh"])
    assert_artifacts()
    assert_tool_behavior()
    assert_routing_behavior()

    # Preserve the original fixed url_tool assertion as well.
    result = run(["./url_tool", "/test/path"])
    assert result.stdout.strip() == "/test/path", \
        "url_tool did not output the expected path."

    # Preserve the original routing assertion.
    result = run(["./test_routing.sh", "http://example.com/some/path?param=value"])
    assert result.stdout.strip() == "/some/path", \
        "test_routing.sh failed to strip query params."

    # Run CI from a clean state and require it to regenerate both build outputs and log.
    clean_artifacts(remove_log=True)
    run(["./ci_run.sh"])
    assert_artifacts()
    assert_tool_behavior()
    assert os.path.isfile(LOG_PATH), "ci_run.sh did not generate ci_success.log."
    with open(LOG_PATH) as f:
        assert f.read().strip() == "CI SUCCESS", "ci_success.log has incorrect content."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
