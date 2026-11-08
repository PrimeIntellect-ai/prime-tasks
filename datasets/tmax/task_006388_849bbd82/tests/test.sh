#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import string
import subprocess
import tempfile

PROJECT_DIR = "/home/user/project"
RESULT_FILE = os.path.join(PROJECT_DIR, "result.txt")
MAKEFILE = os.path.join(PROJECT_DIR, "Makefile")
APP_BIN = os.path.join(PROJECT_DIR, "bin", "app")
BUILD_SYSTEM = os.path.join(PROJECT_DIR, "build_system.py")

EXPECTED_CONTENT = (
    "Running in ARM mode\n"
    "Result: 8\n"
    "String ops loaded.\n"
)


def test_makefile_exists():
    assert os.path.isfile(MAKEFILE), "Makefile was not generated in /home/user/project/."


def test_app_binary_exists():
    assert os.path.isfile(APP_BIN), "The compiled executable /home/user/project/bin/app does not exist."
    assert os.access(APP_BIN, os.X_OK), "The compiled file /home/user/project/bin/app is not executable."


def test_result_txt_exists():
    assert os.path.isfile(RESULT_FILE), "The result file /home/user/project/result.txt does not exist."


def test_result_txt_content():
    with open(RESULT_FILE, "r") as f:
        content = f.read()

    assert content.strip() == EXPECTED_CONTENT.strip(), (
        f"The content of {RESULT_FILE} is incorrect.\n"
        f"Expected:\n{EXPECTED_CONTENT.strip()}\n\n"
        f"Got:\n{content.strip()}"
    )


def test_final_binary_is_real_and_produces_result():
    with open(APP_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "bin/app is not a compiled ELF executable."
    completed = subprocess.run(
        [APP_BIN], cwd=PROJECT_DIR, text=True, capture_output=True, timeout=10
    )
    assert completed.returncode == 0, completed.stderr
    assert completed.stdout.strip() == EXPECTED_CONTENT.strip()


def _identifier(prefix):
    alphabet = string.ascii_lowercase
    return prefix + "_" + "".join(secrets.choice(alphabet) for _ in range(10))


def _make_fixture(root, bridge, side, disconnected, marker):
    os.makedirs(os.path.join(root, "src"))
    os.makedirs(os.path.join(root, "bin"))
    shutil.copy2(BUILD_SYSTEM, os.path.join(root, "build_system.py"))

    import json
    graph = {
        "main": [bridge, side],
        bridge: ["advanced_math"],
        "advanced_math": [],
        side: [],
        disconnected: []
    }
    with open(os.path.join(root, "deps.json"), "w") as f:
        json.dump(graph, f)

    with open(os.path.join(root, "src", "main.c"), "w") as f:
        f.write(f'''#include <stdio.h>
extern int bridge_call(int, int);
extern void side_call(void);
int main(void) {{
#ifdef ARM_MODE
    printf("ARM\\n");
#else
    printf("NATIVE\\n");
#endif
    printf("VALUE:%d\\n", bridge_call(2, 3));
    side_call();
    return 0;
}}
''')
    with open(os.path.join(root, "src", bridge + ".c"), "w") as f:
        f.write('''extern int advanced_math_op(int, int);
int bridge_call(int a, int b) { return advanced_math_op(a, b); }
''')
    with open(os.path.join(root, "src", "advanced_math.c"), "w") as f:
        f.write('''#include <math.h>
int advanced_math_op(int base, int exp) {
    return (int)pow((double)base, (double)exp);
}
''')
    with open(os.path.join(root, "src", side + ".c"), "w") as f:
        f.write(f'''#include <stdio.h>
void side_call(void) {{ printf("{marker}\\n"); }}
''')
    # No source is created for the disconnected graph node. A traversal that
    # incorrectly includes unreachable nodes will therefore fail to build.


def _generate_build_and_run(root, arm):
    env = os.environ.copy()
    if arm:
        env["TARGET_ARCH"] = "arm"
    else:
        env.pop("TARGET_ARCH", None)

    generated = subprocess.run(
        ["python3", "build_system.py"], cwd=root, env=env,
        text=True, capture_output=True, timeout=15
    )
    assert generated.returncode == 0, generated.stdout + generated.stderr
    assert os.path.isfile(os.path.join(root, "Makefile")), "build_system.py did not generate a Makefile"

    built = subprocess.run(
        ["make"], cwd=root, env=env, text=True, capture_output=True, timeout=30
    )
    assert built.returncode == 0, built.stdout + built.stderr

    app = os.path.join(root, "bin", "app")
    assert os.path.isfile(app) and os.access(app, os.X_OK)
    with open(app, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Generated bin/app is not a compiled ELF executable"

    run = subprocess.run([app], cwd=root, text=True, capture_output=True, timeout=10)
    assert run.returncode == 0, run.stderr
    return run.stdout


def test_build_system_behavior_on_fresh_dependency_graphs():
    assert os.path.isfile(BUILD_SYSTEM), "build_system.py is missing"
    bridge = _identifier("bridge")
    side = _identifier("side")
    disconnected = _identifier("unused")
    marker = _identifier("marker")

    with tempfile.TemporaryDirectory(prefix="native_build_") as native_root:
        _make_fixture(native_root, bridge, side, disconnected, marker)
        native_output = _generate_build_and_run(native_root, arm=False)
        assert native_output == f"NATIVE\nVALUE:8\n{marker}\n"

    with tempfile.TemporaryDirectory(prefix="arm_build_") as arm_root:
        _make_fixture(arm_root, bridge, side, disconnected, marker)
        arm_output = _generate_build_and_run(arm_root, arm=True)
        assert arm_output == f"ARM\nVALUE:8\n{marker}\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
