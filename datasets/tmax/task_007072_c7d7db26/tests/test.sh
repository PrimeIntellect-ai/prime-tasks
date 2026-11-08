#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import stat
import subprocess
import tempfile

PROJECT_DIR = "/home/user/waf-project"

ORIGINAL_CI = '''#!/bin/bash

echo "Starting CI Build..."
# TODO: resolve dependencies and set LDFLAGS here

make clean
make

echo "Running tests..."
./waf_engine > build_success.log
'''

EXPECTED_SECURE_C = '''#include <stdio.h>
void secure_func() {
    printf("Secured WAF Engine Running\\n");
}
int main() {
    secure_func();
    return 0;
}
'''


def test_resolve_deps_exists_executable():
    script_path = os.path.join(PROJECT_DIR, "resolve_deps.sh")
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."


def test_flags_txt_content():
    flags_path = os.path.join(PROJECT_DIR, "flags.txt")
    assert os.path.isfile(flags_path), f"File {flags_path} is missing."
    with open(flags_path, "r") as f:
        content = f.read().strip()
    valid_flags = [
        "-lwaf -lparser -lcrypto -llog",
        "-lwaf -lcrypto -lparser -llog",
    ]
    normalized_content = " ".join(content.split())
    assert normalized_content in valid_flags, \
        f"flags.txt content '{normalized_content}' does not match expected topological sort."


def test_waf_engine_patched():
    c_file = os.path.join(PROJECT_DIR, "waf_engine.c")
    assert os.path.isfile(c_file), f"File {c_file} is missing."
    with open(c_file, "r") as f:
        content = f.read()
    assert "insecure_func" not in content, "waf_engine.c still contains 'insecure_func', patch was not applied correctly."
    assert "secure_func" in content, "waf_engine.c does not contain 'secure_func', patch was not applied correctly."
    assert content == EXPECTED_SECURE_C, "waf_engine.c is not the exact result of the supplied security fix."


def test_ci_fix_patch_exists():
    patch_file = os.path.join(PROJECT_DIR, "ci_fix.patch")
    assert os.path.isfile(patch_file), f"File {patch_file} is missing."


def test_build_success_log():
    log_file = os.path.join(PROJECT_DIR, "build_success.log")
    assert os.path.isfile(log_file), f"File {log_file} is missing. Did the CI pipeline run successfully?"
    with open(log_file, "r") as f:
        content = f.read()
    assert "Secured WAF Engine Running" in content, \
        "build_success.log does not contain the expected output 'Secured WAF Engine Running'."


def test_resolver_on_derived_graphs():
    deps_path = os.path.join(PROJECT_DIR, "deps.txt")
    flags_path = os.path.join(PROJECT_DIR, "flags.txt")
    resolver = os.path.join(PROJECT_DIR, "resolve_deps.sh")
    original_deps = open(deps_path, "rb").read()
    original_flags = open(flags_path, "rb").read() if os.path.exists(flags_path) else None

    try:
        for _ in range(4):
            count = random.randint(6, 10)
            nodes = ["n" + secrets.token_hex(4) for _ in range(count)]
            edges = {node: [] for node in nodes}
            for i in range(count):
                for j in range(i + 1, count):
                    if random.random() < 0.32:
                        edges[nodes[i]].append(nodes[j])
            # Ensure the generated graph contains both dependencies and an isolated node.
            edges[nodes[0]].append(nodes[1]) if nodes[1] not in edges[nodes[0]] else None
            edges[nodes[-1]] = []
            lines = []
            order = list(nodes)
            random.shuffle(order)
            for node in order:
                lines.append(f"{node}: {' '.join(edges[node])}".rstrip())
            with open(deps_path, "w") as f:
                f.write("\n".join(lines) + "\n")
            if os.path.exists(flags_path):
                os.unlink(flags_path)
            result = subprocess.run(
                [resolver], cwd=PROJECT_DIR, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
            )
            assert result.returncode == 0, f"resolve_deps.sh failed on a valid DAG: {result.stderr}"
            assert os.path.isfile(flags_path), "resolve_deps.sh did not create flags.txt"
            raw = open(flags_path).read().strip()
            tokens = raw.split()
            assert all(t.startswith("-l") and len(t) > 2 for t in tokens), \
                f"Resolver emitted malformed GCC flags: {raw!r}"
            resolved = [t[2:] for t in tokens]
            assert len(resolved) == len(nodes) and set(resolved) == set(nodes), \
                f"Resolver did not emit every graph node exactly once: {raw!r}"
            positions = {node: i for i, node in enumerate(resolved)}
            for node, dependencies in edges.items():
                for dependency in dependencies:
                    assert positions[node] < positions[dependency], \
                        f"{node} must precede its dependency {dependency}: {raw!r}"
    finally:
        with open(deps_path, "wb") as f:
            f.write(original_deps)
        if original_flags is None:
            if os.path.exists(flags_path):
                os.unlink(flags_path)
        else:
            with open(flags_path, "wb") as f:
                f.write(original_flags)


def test_ci_patch_applies_to_original_and_matches_installed_script():
    patch_file = os.path.join(PROJECT_DIR, "ci_fix.patch")
    installed = open(os.path.join(PROJECT_DIR, "ci_build.sh"), "rb").read()
    applied = None
    errors = []
    for strip in (0, 1):
        with tempfile.TemporaryDirectory() as td:
            ci_path = os.path.join(td, "ci_build.sh")
            with open(ci_path, "w") as f:
                f.write(ORIGINAL_CI)
            proc = subprocess.run(
                ["patch", "--batch", f"-p{strip}", "-i", patch_file],
                cwd=td, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            if proc.returncode == 0:
                applied = open(ci_path, "rb").read()
                break
            errors.append((proc.stdout + proc.stderr).decode(errors="replace"))
    assert applied is not None, "ci_fix.patch does not apply to the original ci_build.sh: " + " | ".join(errors)
    assert applied != ORIGINAL_CI.encode(), "ci_fix.patch does not modify ci_build.sh"
    assert installed == applied, "The installed ci_build.sh is not the result of applying ci_fix.patch"


def test_ci_pipeline_really_resolves_exports_builds_and_runs():
    resolver = os.path.join(PROJECT_DIR, "resolve_deps.sh")
    saved_resolver = os.path.join(PROJECT_DIR, ".resolve_deps.verifier-real")
    marker = os.path.join(PROJECT_DIR, ".resolver-ran")
    env_log = os.path.join(PROJECT_DIR, ".make-ldflags")
    wrapper_dir = tempfile.mkdtemp(prefix="ci-wrappers-")
    make_wrapper = os.path.join(wrapper_dir, "make")

    for path in (marker, env_log, os.path.join(PROJECT_DIR, "flags.txt"),
                 os.path.join(PROJECT_DIR, "build_success.log"),
                 os.path.join(PROJECT_DIR, "waf_engine"),
                 os.path.join(PROJECT_DIR, "waf_engine.o")):
        if os.path.exists(path):
            os.unlink(path)

    os.rename(resolver, saved_resolver)
    try:
        with open(resolver, "w") as f:
            f.write(f'''#!/bin/bash
set -e
printf 'ran\\n' > {marker!r}
exec {saved_resolver!r} "$@"
''')
        os.chmod(resolver, 0o755)
        with open(make_wrapper, "w") as f:
            f.write(f'''#!/bin/bash
if [ ! -f {marker!r} ]; then
    echo "make invoked before resolve_deps.sh" >&2
    exit 97
fi
printf '%s\\n' "${{LDFLAGS-}}" >> {env_log!r}
exec /usr/bin/make "$@"
''')
        os.chmod(make_wrapper, 0o755)

        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
        proc = subprocess.run(
            ["./ci_build.sh"], cwd=PROJECT_DIR, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        assert proc.returncode == 0, \
            f"ci_build.sh failed when genuinely executed:\n{proc.stdout}\n{proc.stderr}"
        assert os.path.isfile(marker), "ci_build.sh did not execute ./resolve_deps.sh"
        assert os.path.isfile(os.path.join(PROJECT_DIR, "flags.txt")), "The pipeline did not generate flags.txt"
        flags = " ".join(open(os.path.join(PROJECT_DIR, "flags.txt")).read().split())
        assert flags in {
            "-lwaf -lparser -lcrypto -llog",
            "-lwaf -lcrypto -lparser -llog",
        }
        observed = [" ".join(x.split()) for x in open(env_log).read().splitlines()]
        assert observed, "ci_build.sh never invoked make"
        assert all(value == flags for value in observed), \
            f"LDFLAGS was not exported from flags.txt before every make invocation: {observed!r}"
        binary = os.path.join(PROJECT_DIR, "waf_engine")
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), "The CI pipeline did not produce an executable"
        run = subprocess.run([binary], cwd=PROJECT_DIR, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert run.returncode == 0, f"Built executable failed: {run.stderr}"
        assert run.stdout.strip() == "Secured WAF Engine Running"
        log = open(os.path.join(PROJECT_DIR, "build_success.log")).read().strip()
        assert log == "Secured WAF Engine Running", "Pipeline did not create the success log from program output"
    finally:
        if os.path.exists(resolver):
            os.unlink(resolver)
        if os.path.exists(saved_resolver):
            os.rename(saved_resolver, resolver)
        for path in (marker, env_log):
            if os.path.exists(path):
                os.unlink(path)
        shutil.rmtree(wrapper_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
