#!/bin/bash
mkdir -p /logs/verifier

cat << 'PLUGIN_EOF' > /tmp/verifier_plugin.py
import json
import os
import sys

TARGET = os.path.realpath('/home/user/polybuild/build_parser.py')
events = []
pending = {}

def _profile(frame, event, arg):
    if os.path.realpath(frame.f_code.co_filename) != TARGET:
        return _profile
    name = frame.f_code.co_name
    if event == 'call' and name in {'check_version', 'parse_poly_file', 'get_build_order'}:
        item = {'function': name}
        if name == 'check_version':
            item['actual'] = frame.f_locals.get('actual')
            item['required'] = frame.f_locals.get('required')
        elif name == 'parse_poly_file':
            item['filepath'] = frame.f_locals.get('filepath')
        else:
            targets = frame.f_locals.get('targets', {})
            try:
                item['targets'] = {
                    str(k): {
                        'version': str(v.get('version', '')),
                        'depends': list(v.get('depends', [])),
                    }
                    for k, v in targets.items()
                }
            except Exception:
                item['targets'] = None
        pending[id(frame)] = item
    elif event == 'return' and id(frame) in pending:
        item = pending.pop(id(frame))
        try:
            item['result'] = arg if isinstance(arg, (str, int, float, bool, list, dict, type(None))) else repr(arg)
        except Exception:
            item['result'] = '<unrepresentable>'
        events.append(item)
    return _profile

def pytest_sessionstart(session):
    sys.setprofile(_profile)

def pytest_sessionfinish(session, exitstatus):
    sys.setprofile(None)
    with open('/tmp/test_parser_events.json', 'w') as f:
        json.dump(events, f)
PLUGIN_EOF

rm -f /tmp/test_parser_events.json /tmp/test_parser_run.log
if timeout 60s env PYTHONPATH="/tmp:${PYTHONPATH:-}" python3 -m pytest -p verifier_plugin /home/user/polybuild/test_parser.py --tb=short > /tmp/test_parser_run.log 2>&1; then
    TEST_SUITE_OK=1
else
    TEST_SUITE_OK=0
fi
export TEST_SUITE_OK

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import random
import re
import subprocess
import sys
import uuid

ROOT = '/home/user/polybuild'
PROJECT = ROOT + '/examples/project.poly'
EXPECTED_PROJECT_ORDER = 'logger, database, api, frontend'


def load_parser():
    path = ROOT + '/build_parser.py'
    assert os.path.isfile(path), f'{path} does not exist.'
    name = 'build_parser_verifier_' + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def assert_valid_order(order, targets):
    assert isinstance(order, list), f'get_build_order must return a list, got {type(order).__name__}'
    assert len(order) == len(targets), f'Order omitted or duplicated targets: {order}'
    assert set(order) == set(targets), f'Order contains the wrong targets: {order}'
    positions = {name: i for i, name in enumerate(order)}
    for target, data in targets.items():
        for dependency in data['depends']:
            dep_name = dependency.split('@>=', 1)[0]
            assert positions[dep_name] < positions[target], (
                f'Dependency {dep_name} must precede {target}; got {order}'
            )


def test_build_order_txt():
    """Verify the generated build_order.txt contains the correct topological sort."""
    build_order_file = "/home/user/polybuild/build_order.txt"
    assert os.path.isfile(build_order_file), f"{build_order_file} does not exist."

    with open(build_order_file, "r") as f:
        content = f.read().strip()

    expected = "logger, database, api, frontend"
    assert content == expected, f"Expected build order '{expected}', but got '{content}'."


def test_test_results_log():
    """Verify that test_results.log was generated and contains genuine successful pytest output."""
    log_file = "/home/user/polybuild/test_results.log"
    assert os.path.isfile(log_file), f"{log_file} does not exist."

    with open(log_file, "r") as f:
        content = f.read()

    assert "passed" in content.lower() or "test session starts" in content, "test_results.log does not look like valid pytest output."
    with open('/tmp/test_parser_run.log', 'r') as f:
        replay = f.read()
    stored_counts = re.findall(r'(\d+)\s+passed\b', content.lower())
    replay_counts = re.findall(r'(\d+)\s+passed\b', replay.lower())
    assert stored_counts, 'test_results.log does not contain a successful pytest summary.'
    assert replay_counts, f'Replayed pytest run has no passing-test summary:\n{replay}'
    assert int(stored_counts[-1]) == int(replay_counts[-1]), (
        'test_results.log does not report the same number of passing tests as the test suite.'
    )


def test_test_parser_exists():
    """Verify that the test suite was created and really passes when executed."""
    test_file = "/home/user/polybuild/test_parser.py"
    assert os.path.isfile(test_file), f"{test_file} does not exist."
    assert os.path.getsize(test_file) > 0, 'test_parser.py is empty.'
    assert os.environ.get('TEST_SUITE_OK') == '1', (
        'Running test_parser.py with pytest failed; see /tmp/test_parser_run.log.'
    )


def test_user_suite_exercises_required_features():
    with open('/tmp/test_parser_events.json', 'r') as f:
        events = json.load(f)

    version_events = [e for e in events if e.get('function') == 'check_version']
    parse_events = [e for e in events if e.get('function') == 'parse_poly_file']
    order_events = [e for e in events if e.get('function') == 'get_build_order']

    assert version_events, 'test_parser.py never calls check_version.'
    assert any(os.path.realpath(str(e.get('filepath'))) == os.path.realpath(PROJECT) for e in parse_events), (
        'test_parser.py does not parse examples/project.poly.'
    )
    project_names = {'frontend', 'api', 'logger', 'database'}
    assert any(isinstance(e.get('targets'), dict) and set(e['targets']) == project_names for e in order_events), (
        'test_parser.py does not exercise topological sorting of the example project.'
    )

    def numeric(v):
        try:
            return tuple(int(x) for x in v.split('.'))
        except Exception:
            return None

    checked = []
    for event in version_events:
        actual = numeric(event.get('actual')) if isinstance(event.get('actual'), str) else None
        required = numeric(event.get('required')) if isinstance(event.get('required'), str) else None
        if actual is not None and required is not None:
            checked.append((actual, required, event.get('result')))
    assert any(a >= r and result is True for a, r, result in checked), 'Tests do not cover a successful version comparison.'
    assert any(a < r and result is False for a, r, result in checked), 'Tests do not cover a failing version comparison.'
    assert any(
        ((a >= r) != ('.'.join(map(str, a)) >= '.'.join(map(str, r))))
        for a, r, _ in checked
    ), 'Tests do not cover a case where string and numeric version ordering differ.'


def test_build_parser_logic():
    """Verify the logic in build_parser.py has been fixed."""
    sys.path.insert(0, "/home/user/polybuild")
    try:
        import build_parser
    except ImportError:
        assert False, "Could not import build_parser.py"

    # Test version logic
    assert hasattr(build_parser, "check_version"), "check_version function is missing."
    # 1.10.0 >= 1.2.0 should be True now
    assert build_parser.check_version("1.10.0", "1.2.0") is True, "check_version failed: 1.10.0 should be >= 1.2.0"
    assert build_parser.check_version("1.2.0", "1.10.0") is False, "check_version failed: 1.2.0 should not be >= 1.10.0"
    assert build_parser.check_version("2.0.0", "2.0.0") is True, "check_version failed: 2.0.0 should be >= 2.0.0"

    # Test graph traversal logic
    assert hasattr(build_parser, "get_build_order"), "get_build_order function is missing."

    mock_targets = {
        'A': {'version': '1.0.0', 'depends': ['B@>=1.0.0']},
        'B': {'version': '1.0.0', 'depends': ['C@>=1.0.0']},
        'C': {'version': '1.0.0', 'depends': []}
    }

    try:
        order = build_parser.get_build_order(mock_targets)
    except Exception as e:
        assert False, f"get_build_order raised an exception: {e}"

    assert order == ['C', 'B', 'A'], f"get_build_order returned {order}, expected ['C', 'B', 'A']"


def test_random_semantic_versions():
    parser = load_parser()
    rng = random.SystemRandom()
    for _ in range(120):
        actual_tuple = tuple(rng.randrange(0, 1000) for _ in range(3))
        required_tuple = tuple(rng.randrange(0, 1000) for _ in range(3))
        actual = '.'.join(map(str, actual_tuple))
        required = '.'.join(map(str, required_tuple))
        result = parser.check_version(actual, required)
        assert isinstance(result, bool)
        assert result == (actual_tuple >= required_tuple), (
            f'Incorrect comparison: {actual} >= {required} returned {result}'
        )


def test_random_topological_graphs():
    parser = load_parser()
    rng = random.SystemRandom()
    for _ in range(20):
        count = rng.randrange(7, 20)
        nonce = uuid.uuid4().hex[:10]
        names = [f'n_{nonce}_{i}' for i in range(count)]
        targets = {}
        for i, name in enumerate(names):
            possible = list(range(i))
            rng.shuffle(possible)
            dep_indices = possible[:rng.randrange(0, min(4, len(possible)) + 1)]
            major, minor, patch = (rng.randrange(1, 40) for _ in range(3))
            targets[name] = {
                'version': f'{major}.{minor}.{patch}',
                'depends': [f'{names[j]}@>=0.0.0' for j in dep_indices],
            }
        items = list(targets.items())
        rng.shuffle(items)
        shuffled_targets = dict(items)
        assert_valid_order(parser.get_build_order(shuffled_targets), shuffled_targets)


def test_dynamic_dependency_errors():
    parser = load_parser()
    nonce = uuid.uuid4().hex
    missing = {
        nonce: {'version': '1.0.0', 'depends': [f'missing_{nonce}@>=1.0.0']}
    }
    try:
        parser.get_build_order(missing)
    except ValueError:
        pass
    else:
        assert False, 'Missing dependencies must raise ValueError.'

    dep = 'dep_' + nonce
    root = 'root_' + nonce
    mismatch = {
        dep: {'version': '1.9.9', 'depends': []},
        root: {'version': '1.0.0', 'depends': [f'{dep}@>=1.10.0']},
    }
    try:
        parser.get_build_order(mismatch)
    except ValueError:
        pass
    else:
        assert False, 'Unsatisfied semantic-version requirements must raise ValueError.'


def test_parser_and_cli_on_project():
    parser = load_parser()
    targets = parser.parse_poly_file(PROJECT)
    assert set(targets) == {'frontend', 'api', 'logger', 'database'}
    assert targets['api']['version'] == '1.12.5'
    assert targets['frontend']['depends'] == ['api@>=1.10.0', 'logger@>=2.0.0']
    assert_valid_order(parser.get_build_order(targets), targets)

    completed = subprocess.run(
        [sys.executable, ROOT + '/build_parser.py', PROJECT],
        text=True, capture_output=True, timeout=15
    )
    assert completed.returncode == 0, completed.stderr
    assert completed.stdout.strip() == EXPECTED_PROJECT_ORDER
    with open(ROOT + '/build_order.txt', 'r') as f:
        assert completed.stdout.strip() == f.read().strip()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
