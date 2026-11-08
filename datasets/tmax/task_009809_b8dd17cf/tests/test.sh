#!/bin/bash
set -e
mkdir -p /logs/verifier

VERIFY_TMP=$(mktemp -d)
export VERIFY_TMP
export CI_TEST_PROBE="$VERIFY_TMP/test-ran"
export CI_TOOL_LOG="$VERIFY_TMP/tools.log"
mkdir -p "$VERIFY_TMP/bin"

cat > "$VERIFY_TMP/probe.cpp" <<'EOF'
#include <cstdlib>
#include <fstream>
struct VerificationProbe {
    VerificationProbe() {
        const char *path = std::getenv("CI_TEST_PROBE");
        if (path) std::ofstream(path, std::ios::app) << "ran\n";
    }
};
static VerificationProbe verification_probe;
EOF

cat > "$VERIFY_TMP/bin/g++" <<'EOF'
#!/bin/bash
{
    printf 'g++'
    printf '\t%q' "$@"
    printf '\n'
} >> "$CI_TOOL_LOG"
is_test=0
is_link=1
for arg in "$@"; do
    case "$arg" in
        *test_semver.cpp) is_test=1 ;;
        -c|-E|-S) is_link=0 ;;
    esac
done
if [ "$is_test" -eq 1 ] && [ "$is_link" -eq 1 ]; then
    exec /usr/bin/g++ "$@" "$VERIFY_TMP/probe.cpp"
else
    exec /usr/bin/g++ "$@"
fi
EOF
chmod +x "$VERIFY_TMP/bin/g++"

cat > "$VERIFY_TMP/bin/c++" <<'EOF'
#!/bin/bash
exec "$(dirname "$0")/g++" "$@"
EOF
chmod +x "$VERIFY_TMP/bin/c++"

cat > "$VERIFY_TMP/bin/python3" <<'EOF'
#!/bin/bash
{
    printf 'python3'
    printf '\t%q' "$@"
    printf '\n'
} >> "$CI_TOOL_LOG"
exec /usr/bin/python3 "$@"
EOF
chmod +x "$VERIFY_TMP/bin/python3"

export PATH="$VERIFY_TMP/bin:$PATH"

cat <<'TEST_EOF' > "$VERIFY_TMP/test_final_state.py"
import json
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

PROJECT_DIR = '/home/user/project'
VERIFY_TMP = os.environ['VERIFY_TMP']
TOOL_LOG = os.environ['CI_TOOL_LOG']
PROBE = os.environ['CI_TEST_PROBE']


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kwargs)


def test_wrapper_is_valid_python3():
    wrapper_path = os.path.join(PROJECT_DIR, 'wrapper.py')
    assert os.path.isfile(wrapper_path), f"{wrapper_path} does not exist"

    result = run(['python3', '-m', 'py_compile', wrapper_path])
    assert result.returncode == 0, f"wrapper.py is not valid Python 3. Error:\n{result.stderr}"

    with open(wrapper_path, 'r') as f:
        content = f.read()
    assert 'print ' not in content, "Python 2 print statement still exists in wrapper.py"
    assert '.iteritems()' not in content, "Python 2 iteritems() still exists in wrapper.py"


def test_wrapper_really_invokes_solver_and_transports_json():
    wrapper = os.path.join(PROJECT_DIR, 'wrapper.py')
    with tempfile.TemporaryDirectory() as td:
        sentinel = 'verified-' + uuid.uuid4().hex
        recorded = os.path.join(td, 'stdin.txt')
        fake_solver = os.path.join(td, 'solver')
        with open(fake_solver, 'w') as f:
            f.write('#!/usr/bin/python3\n')
            f.write('import json, sys\n')
            f.write(f'open({recorded!r}, "w").write(sys.stdin.read())\n')
            f.write(f'print(json.dumps({{"sentinel": {sentinel!r}}}))\n')
        os.chmod(fake_solver, 0o755)

        request = os.path.join(td, 'request.json')
        with open(request, 'w') as f:
            json.dump({'alpha': '>=3.4.5', 'beta': '<9.0.0'}, f)

        result = run(['python3', wrapper, request], cwd=td)
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout) == {'sentinel': sentinel}, result.stdout
        assert os.path.isfile(recorded), 'wrapper did not execute the solver'
        with open(recorded) as f:
            lines = f.read().splitlines()
        assert set(lines) == {'alpha:>=3.4.5', 'beta:<9.0.0'}


def test_test_semver_cpp_exists_and_includes_rapidcheck():
    test_file = os.path.join(PROJECT_DIR, 'test_semver.cpp')
    assert os.path.isfile(test_file), f"{test_file} does not exist"

    with open(test_file, 'r') as f:
        content = f.read()
    assert '<rapidcheck.h>' in content, "test_semver.cpp does not include <rapidcheck.h>"
    assert 'compare_versions' in content, "test_semver.cpp does not test compare_versions"


def test_ci_sh_exists_and_executable():
    ci_script = os.path.join(PROJECT_DIR, 'ci.sh')
    assert os.path.isfile(ci_script), f"{ci_script} does not exist"
    assert os.access(ci_script, os.X_OK), f"{ci_script} is not executable"


def test_ci_propagates_property_test_failure():
    ci_script = os.path.join(PROJECT_DIR, 'ci.sh')
    test_file = os.path.join(PROJECT_DIR, 'test_semver.cpp')
    with open(test_file, 'rb') as f:
        original = f.read()
    mode = stat.S_IMODE(os.stat(test_file).st_mode)
    try:
        with open(test_file, 'w') as f:
            f.write('#include <rapidcheck.h>\nint main() { return 23; }\n')
        result = run(['bash', ci_script], cwd=PROJECT_DIR)
        assert result.returncode != 0, (
            'ci.sh ignored a failing property-test executable.\n'
            f'Stdout: {result.stdout}\nStderr: {result.stderr}'
        )
    finally:
        with open(test_file, 'wb') as f:
            f.write(original)
        os.chmod(test_file, mode)


def test_ci_sh_execution_and_output():
    ci_script = os.path.join(PROJECT_DIR, 'ci.sh')
    for name in ['solver', 'test_semver', 'semver_test', 'tests', 'a.out', 'output.json']:
        path = os.path.join(PROJECT_DIR, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)
    open(TOOL_LOG, 'w').close()
    if os.path.exists(PROBE):
        os.remove(PROBE)

    result = run(['bash', ci_script], cwd=PROJECT_DIR)
    assert result.returncode == 0, (
        f"ci.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    output_file = os.path.join(PROJECT_DIR, 'output.json')
    assert os.path.isfile(output_file), f"{output_file} was not generated"
    with open(output_file, 'r') as f:
        content = f.read()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"{output_file} does not contain valid JSON.\nContent:\n{content}")
    assert data.get('status') == 'resolved_correctly', (
        f"Expected status 'resolved_correctly', got {data.get('status')}"
    )
    assert data == {'status': 'resolved_correctly'}

    solver = os.path.join(PROJECT_DIR, 'solver')
    assert os.path.isfile(solver) and os.access(solver, os.X_OK), 'CI did not build executable solver'
    solver_result = run([solver], input='probe:>=1.0.0\n', cwd=PROJECT_DIR)
    assert solver_result.returncode == 0
    assert json.loads(solver_result.stdout) == {'status': 'resolved_correctly'}

    with open(TOOL_LOG) as f:
        log = f.read()
    for source in ['solver.cpp', 'semver.cpp', 'graph.cpp', 'test_semver.cpp']:
        assert source in log, f'CI did not compile {source}'
    assert re.search(r'(librapidcheck\.a|-lrapidcheck)', log), 'CI did not link RapidCheck'
    assert re.search(r'python3[^\n]*wrapper\.py[^\n]*input\.json', log), (
        'CI did not run python3 wrapper.py input.json'
    )
    assert os.path.isfile(PROBE) and os.path.getsize(PROBE) > 0, (
        'The property-test executable was compiled but was not run'
    )


def test_semver_cpp_fixed():
    semver_file = os.path.join(PROJECT_DIR, 'semver.cpp')
    assert os.path.isfile(semver_file), f"{semver_file} does not exist"
    with open(semver_file, 'r') as f:
        content = f.read()
    assert 'a > b ? 1 : -1' not in content, "Buggy string comparison still exists in semver.cpp"


def test_semver_numeric_comparison_and_properties():
    harness = os.path.join(VERIFY_TMP, 'semver_harness.cpp')
    executable = os.path.join(VERIFY_TMP, 'semver_harness')
    with open(harness, 'w') as f:
        f.write(r'''#include "semver.h"
#include <iostream>
#include <string>
int main() {
    std::string a, b;
    while (std::cin >> a >> b)
        std::cout << compare_versions(a, b) << "\n";
    return 0;
}
''')
    compiled = run([
        '/usr/bin/g++', '-std=c++17', '-I' + PROJECT_DIR, harness,
        os.path.join(PROJECT_DIR, 'semver.cpp'), '-o', executable
    ])
    assert compiled.returncode == 0, compiled.stderr

    rng = random.SystemRandom()
    pairs = [
        ('1.2.0', '1.10.0'), ('2.0.0', '1.99.99'),
        ('1.0.10', '1.0.2'), ('0.0.0', '0.0.0'),
        ('10.20.30', '10.20.30'), ('7.0.0', '7.0.1'),
        ('1.02.003', '1.2.3')
    ]
    for _ in range(250):
        av = tuple(rng.randrange(0, 100000) for _ in range(3))
        bv = tuple(rng.randrange(0, 100000) for _ in range(3))
        pairs.append(('.'.join(map(str, av)), '.'.join(map(str, bv))))
    versions = [v for pair in pairs[:80] for v in pair]
    pairs.extend((v, v) for v in versions)
    pairs.extend((b, a) for a, b in list(pairs))

    expected = []
    for a, b in pairs:
        aa = tuple(map(int, a.split('.')))
        bb = tuple(map(int, b.split('.')))
        expected.append((aa > bb) - (aa < bb))
    payload = ''.join(f'{a} {b}\n' for a, b in pairs)
    result = run([executable], input=payload)
    assert result.returncode == 0, result.stderr
    try:
        actual = [int(x) for x in result.stdout.splitlines()]
    except ValueError:
        pytest.fail(f'compare_versions harness emitted non-integer output: {result.stdout!r}')
    assert actual == expected, 'compare_versions failed numeric Major.Minor.Patch comparisons'

    observed = {(a, b): value for (a, b), value in zip(pairs, actual)}
    for v in versions:
        assert observed[(v, v)] == 0, 'equality symmetry property failed'
    for a, b in pairs:
        value = observed[(a, b)]
        reverse = observed[(b, a)]
        if value == 1:
            assert reverse == -1, 'anti-symmetry property failed'
        if value == -1:
            assert reverse == 1, 'anti-symmetry property failed'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$VERIFY_TMP/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$VERIFY_TMP"
