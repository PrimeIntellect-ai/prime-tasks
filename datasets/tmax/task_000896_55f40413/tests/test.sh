#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_resolution_tool.py
import json
import os
import random
import subprocess
from pathlib import Path

HOME = Path('/home/user')
REGISTRY = HOME / 'registry.json'
OUTPUT = HOME / 'resolutions.txt'
TARGETS = [('app_alpha', '1.0.0'), ('app_beta', '2.1.0'), ('app_gamma', '3.0.0')]

ORIGINAL_EXPECTED = {
    'app_alpha@1.0.0': [
        'app_alpha@1.0.0',
        'lib_core@1.2.0',
        'lib_crypto@1.0.0',
        'lib_net@2.0.0',
        'lib_utils@2.1.0',
    ],
    'app_beta@2.1.0': [
        'app_beta@2.1.0',
        'lib_auth@2.0.0',
        'lib_core@2.0.0',
        'lib_crypto@2.1.0',
        'lib_utils@2.1.0',
    ],
    'app_gamma@3.0.0': [
        'app_gamma@3.0.0',
        'lib_core@1.2.0',
        'lib_crypto@1.0.0',
        'lib_utils@2.1.0',
    ],
}


def parse_version(value):
    parts = value.split('.')
    if len(parts) != 3 or any(not part.isdigit() for part in parts):
        raise AssertionError(f'Invalid semantic version: {value}')
    return tuple(int(part) for part in parts)


def satisfies(version, constraint):
    for operator in ('==', '>=', '<='):
        if constraint.startswith(operator):
            wanted = parse_version(constraint[len(operator):])
            actual = parse_version(version)
            if operator == '==':
                return actual == wanted
            if operator == '>=':
                return actual >= wanted
            return actual <= wanted
    raise AssertionError(f'Unsupported constraint: {constraint}')


def solve_target(registry, target, target_version):
    packages = registry['packages']
    solutions = []

    def search(selected, constraints):
        for package, version in selected.items():
            if any(not satisfies(version, c) for c in constraints.get(package, [])):
                return

        unresolved = sorted(package for package in constraints if package not in selected)
        if not unresolved:
            solutions.append(dict(selected))
            return

        package = unresolved[0]
        if package not in packages:
            return
        candidates = sorted(packages[package], key=parse_version, reverse=True)
        for version in candidates:
            if not all(satisfies(version, c) for c in constraints[package]):
                continue
            next_selected = dict(selected)
            next_selected[package] = version
            next_constraints = {name: list(items) for name, items in constraints.items()}
            dependencies = packages[package][version].get('depends', {})
            for dependency, constraint in dependencies.items():
                next_constraints.setdefault(dependency, []).append(constraint)
            search(next_selected, next_constraints)

    search({}, {target: ['==' + target_version]})
    if not solutions:
        raise AssertionError(f'No valid resolution for {target}@{target_version}')

    names = sorted(solutions[0])
    assert all(sorted(solution) == names for solution in solutions), 'Fixture has ambiguous package closure'
    return max(solutions, key=lambda solution: tuple(parse_version(solution[name]) for name in names))


def expected_output(registry):
    blocks = []
    for target, version in TARGETS:
        resolution = solve_target(registry, target, version)
        lines = [f'[{target}@{version}]']
        lines.extend(f'{name}@{resolution[name]}' for name in sorted(resolution))
        blocks.append('\n'.join(lines))
    return '\n\n'.join(blocks)


def check_original_assertions():
    assert OUTPUT.exists(), f'Missing required file: {OUTPUT}'
    assert OUTPUT.is_file(), f'Path is not a file: {OUTPUT}'
    content = OUTPUT.read_text().strip()
    assert content, 'resolutions.txt is empty'

    blocks = content.split('\n\n')
    parsed = {}
    for block in blocks:
        lines = [line.strip() for line in block.split('\n') if line.strip()]
        if not lines:
            continue
        header = lines[0]
        assert header.startswith('[') and header.endswith(']'), f'Invalid header format: {header}'
        parsed[header[1:-1]] = lines[1:]

    for target, expected_dependencies in ORIGINAL_EXPECTED.items():
        assert target in parsed, f"Target '{target}' is missing from resolutions.txt"
        assert parsed[target] == expected_dependencies, (
            f"Dependencies for '{target}' do not match expected. "
            f'Expected: {expected_dependencies}; got: {parsed[target]}'
        )
    for target in parsed:
        assert target in ORIGINAL_EXPECTED, f"Unexpected target '{target}' found in resolutions.txt"


def package(versions):
    return {version: {'depends': dependencies} for version, dependencies in versions.items()}


def fixture_one(rng):
    a, b, c = (rng.randint(1, 8) for _ in range(3))
    low, middle, high = f'1.2.{a}', f'1.5.{b}', f'2.0.{c}'
    return {'packages': {
        'app_alpha': package({'1.0.0': {'chooser': '>=1.0.0', 'limiter': '==1.0.0'}}),
        'app_beta': package({'2.1.0': {'selector': '>=1.0.0', 'token_cap': '==1.0.0'}}),
        'app_gamma': package({'3.0.0': {'shared': '>=1.0.0'}}),
        'chooser': package({
            '1.0.0': {'shared': '>=' + low},
            '2.0.0': {'shared': '>=' + high},
        }),
        'limiter': package({'1.0.0': {'shared': '<=' + middle}}),
        'shared': package({low: {}, middle: {}, high: {}}),
        'selector': package({
            '1.0.0': {'token': '>=1.1.0'},
            '2.0.0': {'token': '>=2.0.0'},
        }),
        'token_cap': package({'1.0.0': {'token': '<=1.5.9'}}),
        'token': package({'1.1.0': {}, '1.5.9': {}, '2.0.0': {}}),
    }}


def fixture_two(rng):
    a, b, c = (rng.randint(1, 8) for _ in range(3))
    v19, v110, v111 = f'1.9.{a}', f'1.10.{b}', f'1.11.{c}'
    return {'packages': {
        'app_alpha': package({'1.0.0': {'left': '==1.0.0', 'right': '==1.0.0'}}),
        'app_beta': package({'2.1.0': {'adapter': '==1.0.0', 'auth_choice': '>=1.0.0'}}),
        'app_gamma': package({'3.0.0': {'utility': '>=1.0.0'}}),
        'left': package({'1.0.0': {'common': '>=' + v19}}),
        'right': package({'1.0.0': {'common': '<=' + v110}}),
        'common': package({v19: {}, v110: {}, v111: {}}),
        'adapter': package({'1.0.0': {'engine': '<=2.5.0'}}),
        'auth_choice': package({
            '1.0.0': {'engine': '>=2.0.0'},
            '2.0.0': {'engine': '>=3.0.0'},
        }),
        'engine': package({'2.0.0': {}, '2.5.0': {}, '3.0.0': {}}),
        'utility': package({
            '1.0.0': {'pin': '>=1.0.0'},
            '2.0.0': {'pin': '==1.0.0'},
        }),
        'pin': package({'1.0.0': {}, '2.0.0': {}}),
    }}


def find_candidates():
    candidates = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path in (REGISTRY, OUTPUT):
            continue
        try:
            first_line = path.open('rb').readline(256).lower()
        except OSError:
            continue
        if path.suffix == '.sh' or b'bash' in first_line or os.access(path, os.X_OK):
            candidates.append(path)
    return sorted(candidates)


def run_script(script, registry):
    REGISTRY.write_text(json.dumps(registry, indent=2) + '\n')
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()
    completed = subprocess.run(
        ['/bin/bash', str(script)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f'{script} exited with {completed.returncode}: {completed.stderr[-1000:]}'
    )
    assert OUTPUT.exists() and OUTPUT.is_file(), f'{script} did not create resolutions.txt'


def verify_candidate(script, original, dynamic_fixtures):
    run_script(script, original)
    check_original_assertions()

    for registry in dynamic_fixtures:
        run_script(script, registry)
        actual = OUTPUT.read_text().strip()
        expected = expected_output(registry).strip()
        assert actual == expected, (
            f'{script} produced an incorrect dynamic resolution.\n'
            f'Expected:\n{expected}\n\nGot:\n{actual}'
        )


def main():
    original_bytes = REGISTRY.read_bytes()
    original = json.loads(original_bytes)
    rng = random.SystemRandom()
    fixtures = [fixture_one(rng), fixture_two(rng)]
    candidates = find_candidates()
    assert candidates, 'No Bash dependency-resolution script found under /home/user'

    failures = []
    accepted = None
    try:
        for candidate in candidates:
            try:
                verify_candidate(candidate, original, fixtures)
                accepted = candidate
                break
            except Exception as error:
                failures.append(f'{candidate}: {error}')
        assert accepted is not None, 'No Bash resolver passed the required executions:\n' + '\n'.join(failures)
    finally:
        REGISTRY.write_bytes(original_bytes)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_resolution_tool.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
