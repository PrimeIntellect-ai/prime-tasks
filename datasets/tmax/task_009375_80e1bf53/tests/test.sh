#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess

PROJECT_DIR = "/home/user/project"
LIBWEB_SO = os.path.join(PROJECT_DIR, "libweb.so")
TEST_DEPLOY = os.path.join(PROJECT_DIR, "test_deploy")
TEST_SOURCE = os.path.join(PROJECT_DIR, "test_deploy.c")
MAKEFILE = os.path.join(PROJECT_DIR, "Makefile")
DEPLOYMENT_LOG = "/home/user/deployment_log.txt"


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_complete_deployment_workflow():
    assert os.path.isfile(MAKEFILE), f"Makefile {MAKEFILE} is missing."
    assert os.path.isfile(TEST_SOURCE), f"Deployment test source {TEST_SOURCE} is missing."

    with open(os.path.join(PROJECT_DIR, "router.h"), encoding="utf-8") as f:
        router_h = f.read()
    with open(os.path.join(PROJECT_DIR, "endpoint.h"), encoding="utf-8") as f:
        endpoint_h = f.read()

    forward_decl = re.compile(
        r"(?:typedef\s+struct\s+(?:Router|Endpoint)\s+(?:Router|Endpoint)\s*;|"
        r"struct\s+(?:Router|Endpoint)\s*;)"
    )
    assert forward_decl.search(router_h) or forward_decl.search(endpoint_h), \
        "router.h and endpoint.h must use a forward declaration to break the dependency."
    router_includes_endpoint = re.search(r'#\s*include\s*[<\"]endpoint\.h[>\"]', router_h)
    endpoint_includes_router = re.search(r'#\s*include\s*[<\"]router\.h[>\"]', endpoint_h)
    assert not (router_includes_endpoint and endpoint_includes_router), \
        "router.h and endpoint.h still directly include each other."

    # Force the submitted Makefile's default target and test_deploy target to
    # recreate their demanded artifacts.
    if os.path.exists(LIBWEB_SO):
        os.remove(LIBWEB_SO)
    run(["make", "-B"], cwd=PROJECT_DIR)
    assert os.path.isfile(LIBWEB_SO), "The Makefile default target did not build libweb.so."

    if os.path.exists(TEST_DEPLOY):
        os.remove(TEST_DEPLOY)
    run(["make", "-B", "test_deploy"], cwd=PROJECT_DIR)

    # Original shared-object assertion.
    assert os.path.isfile(LIBWEB_SO), f"Shared library {LIBWEB_SO} is missing."
    result = run(["file", LIBWEB_SO])
    assert "shared object" in result.stdout.lower() or "dynamically linked" in result.stdout.lower(), \
        f"{LIBWEB_SO} does not appear to be a shared object. Output: {result.stdout}"

    # Original executable/linkage assertions.
    assert os.path.isfile(TEST_DEPLOY), f"Executable {TEST_DEPLOY} is missing."
    assert os.access(TEST_DEPLOY, os.X_OK), f"File {TEST_DEPLOY} is not executable."
    result = run(["ldd", TEST_DEPLOY])
    assert "libweb.so" in result.stdout, \
        f"{TEST_DEPLOY} is not dynamically linked to libweb.so. ldd output: {result.stdout}"

    runtime_env = os.environ.copy()
    runtime_env["LD_LIBRARY_PATH"] = PROJECT_DIR + os.pathsep + runtime_env.get("LD_LIBRARY_PATH", "")

    # Exercise the submitted library independently on a verifier-selected input.
    raw = "route " + secrets.token_hex(5) + " data view"
    expected = raw.replace(" ", "%20")
    harness = f'''
#include <stdio.h>
#include <string.h>
#include "router.h"
#include "endpoint.h"
#include "encode.h"
int main(void) {{
    Router router;
    Endpoint endpoint;
    char encoded[512];
    init_router(&router);
    if (router.count != 0) return 10;
    url_encode({json.dumps(raw)}, encoded);
    if (strcmp(encoded, {json.dumps(expected)}) != 0) return 11;
    init_endpoint(&endpoint, encoded, &router);
    if (strcmp(endpoint.path, {json.dumps(expected)}) != 0) return 12;
    if (endpoint.parent != &router) return 13;
    add_endpoint(&router, &endpoint);
    if (router.count != 1) return 14;
    if (router.endpoints[0] != &endpoint) return 15;
    if (strcmp(router.endpoints[0]->path, {json.dumps(expected)}) != 0) return 16;
    return 0;
}}
'''
    with open("/tmp/library_probe.c", "w", encoding="utf-8") as f:
        f.write(harness)
    run([
        "gcc", "/tmp/library_probe.c", "-I", PROJECT_DIR, "-L", PROJECT_DIR,
        "-lweb", "-Wl,-rpath," + PROJECT_DIR, "-o", "/tmp/library_probe"
    ])
    run(["/tmp/library_probe"], env=runtime_env)

    # Compile the submitted deployment source against instrumented API functions.
    # The randomized values ensure it really performs the required call chain and
    # writes router.endpoints[0]->path rather than hardcoding the known answer.
    token = secrets.token_hex(8)
    encoded_marker = "encoded_" + token
    final_marker = "array_" + token
    decoy_marker = "direct_" + token
    stub = f'''
#include <stdlib.h>
#include <string.h>
#include "router.h"
#include "endpoint.h"
#include "encode.h"
static int stage = 0;
static Endpoint stored;
void init_router(Router *r) {{
    if (!r || stage != 0) exit(40);
    r->count = 0;
    stage = 1;
}}
void url_encode(const char *src, char *dest) {{
    if (stage != 1 || strcmp(src, "api/v1/data view") != 0) exit(41);
    strcpy(dest, {json.dumps(encoded_marker)});
    stage = 2;
}}
void init_endpoint(Endpoint *e, const char *path, Router *parent) {{
    if (stage != 2 || !e || !parent || strcmp(path, {json.dumps(encoded_marker)}) != 0) exit(42);
    strcpy(e->path, path);
    e->parent = parent;
    stage = 3;
}}
void add_endpoint(Router *r, Endpoint *e) {{
    if (stage != 3 || !r || !e || e->parent != r || strcmp(e->path, {json.dumps(encoded_marker)}) != 0) exit(43);
    strcpy(stored.path, {json.dumps(final_marker)});
    stored.parent = r;
    strcpy(e->path, {json.dumps(decoy_marker)});
    r->endpoints[0] = &stored;
    r->count = 1;
    stage = 4;
}}
'''
    with open("/tmp/deploy_stub.c", "w", encoding="utf-8") as f:
        f.write(stub)
    run([
        "gcc", TEST_SOURCE, "/tmp/deploy_stub.c", "-I", PROJECT_DIR,
        "-o", "/tmp/test_deploy_probe"
    ])
    if os.path.exists(DEPLOYMENT_LOG):
        os.remove(DEPLOYMENT_LOG)
    run(["/tmp/test_deploy_probe"], cwd=PROJECT_DIR)
    assert os.path.isfile(DEPLOYMENT_LOG), "test_deploy.c did not create the deployment log."
    with open(DEPLOYMENT_LOG, encoding="utf-8") as f:
        assert f.read() == final_marker, \
            "test_deploy.c did not write the first endpoint path produced through the required API calls."

    # Finally execute the Makefile-built, libweb-linked deployment binary from a
    # clean log state, then retain the original exact-content assertion.
    os.remove(DEPLOYMENT_LOG)
    run([TEST_DEPLOY], cwd=PROJECT_DIR, env=runtime_env)
    assert os.path.isfile(DEPLOYMENT_LOG), f"Deployment log {DEPLOYMENT_LOG} is missing."
    with open(DEPLOYMENT_LOG, "r", encoding="utf-8") as f:
        content = f.read()
    expected_content = "api/v1/data%20view"
    assert content == expected_content, \
        f"Content of {DEPLOYMENT_LOG} is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
