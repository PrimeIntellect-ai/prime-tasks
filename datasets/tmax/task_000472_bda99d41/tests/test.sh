#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import inspect
import json
import os
from pathlib import Path
import random
import string
import sys
import pytest

VENDOR_ROOT = Path('/app/vendored/mail-sender-v2').resolve()
PREFIX = '/mnt/backup_restores/'
FORBIDDEN = '&|;$><`\\!'


def expected_safe(path):
    return (
        isinstance(path, str)
        and path.startswith(PREFIX)
        and '..' not in path
        and not any(ch.isspace() for ch in path)
        and not any(ch in FORBIDDEN for ch in path)
        and len(path) >= 22
    )


def call_and_check(is_safe, path):
    try:
        result = is_safe(path)
    except Exception as exc:
        pytest.fail(f'is_safe_backup_path raised {type(exc).__name__} for {path!r}: {exc}')
    assert type(result) is bool, f'is_safe_backup_path must return bool for {path!r}, got {type(result).__name__}'
    assert result is expected_safe(path), f'incorrect classification for generated path {path!r}'


def test_vendored_package_fixed_and_installed(monkeypatch):
    setup_file = VENDOR_ROOT / 'setup.py'
    connection_file = VENDOR_ROOT / 'mail_sender' / 'connection.py'
    assert setup_file.is_file(), f'Missing {setup_file}'
    assert connection_file.is_file(), f'Missing {connection_file}'

    setup_tree = ast.parse(setup_file.read_text(encoding='utf-8'), filename=str(setup_file))
    install_requires = None
    for node in ast.walk(setup_tree):
        if isinstance(node, ast.Call) and any(
            isinstance(kw, ast.keyword) and kw.arg == 'install_requires' for kw in node.keywords
        ):
            for kw in node.keywords:
                if kw.arg == 'install_requires':
                    install_requires = ast.literal_eval(kw.value)
    assert install_requires is not None, 'setup.py has no install_requires argument'
    assert install_requires == ['requests', 'urllib3'], (
        "setup.py install_requires must contain separate 'requests' and 'urllib3' entries"
    )

    connection_source = connection_file.read_text(encoding='utf-8')
    assert 'MAIL_PORT_OVERRIDE' not in connection_source, 'connection.py still references MAIL_PORT_OVERRIDE'
    assert 'SMTP_PORT' in connection_source, 'connection.py does not reference SMTP_PORT'

    try:
        import mail_sender
        import mail_sender.connection
    except ImportError as exc:
        pytest.fail(f'Failed to import mail_sender. Ensure pip install -e was run: {exc}')

    imported_root = Path(mail_sender.__file__).resolve().parent
    assert imported_root == VENDOR_ROOT / 'mail_sender', (
        f'mail_sender imported from {imported_root}, not the vendored source tree'
    )

    try:
        dist = importlib.metadata.distribution('mail-sender-v2')
        direct_url_text = dist.read_text('direct_url.json')
    except importlib.metadata.PackageNotFoundError:
        pytest.fail('mail-sender-v2 is not installed as a distribution')
    assert direct_url_text, 'mail-sender-v2 lacks editable-install metadata (direct_url.json)'
    direct_url = json.loads(direct_url_text)
    assert direct_url.get('dir_info', {}).get('editable') is True, 'mail-sender-v2 was not installed editable'
    installed_url = direct_url.get('url', '')
    assert installed_url.startswith('file:'), 'Editable installation does not point to a local source tree'
    from urllib.parse import unquote, urlparse
    installed_path = Path(unquote(urlparse(installed_url).path)).resolve()
    assert installed_path == VENDOR_ROOT, f'Editable installation points to {installed_path}, not {VENDOR_ROOT}'

    monkeypatch.delenv('MAIL_PORT_OVERRIDE', raising=False)
    monkeypatch.setenv('SMTP_PORT', '2526')
    assert mail_sender.connection.connect() == 'Connected on 2526', 'connect() did not use SMTP_PORT'

    monkeypatch.delenv('SMTP_PORT', raising=False)
    try:
        result = mail_sender.connection.connect()
        assert result is not None, 'connect() returned None'
        assert result == 'Connected on 25', 'connect() did not use the expected port-25 fallback'
    except KeyError as exc:
        if 'MAIL_PORT_OVERRIDE' in str(exc):
            pytest.fail('mail_sender/connection.py still references MAIL_PORT_OVERRIDE without a fallback')
        pytest.fail(f'mail_sender.connection.connect() raised unexpected KeyError: {exc}')
    except Exception as exc:
        pytest.fail(f'mail_sender.connection.connect() raised unexpected exception: {exc}')


def test_path_checker_adversarial_corpus_and_generated_cases():
    checker_file = Path('/home/user/path_checker.py')
    assert checker_file.is_file(), f'File {checker_file} is missing'

    sys.path.insert(0, '/home/user')
    try:
        import path_checker
    except ImportError as exc:
        pytest.fail(f'Failed to import path_checker: {exc}')

    assert hasattr(path_checker, 'is_safe_backup_path'), 'is_safe_backup_path is missing'
    is_safe = path_checker.is_safe_backup_path
    assert callable(is_safe), 'is_safe_backup_path is not callable'
    signature = inspect.signature(is_safe)
    assert list(signature.parameters) == ['path'], f'Expected one parameter named path, got {signature}'

    clean_file = Path('/app/corpora/clean/paths.txt')
    evil_file = Path('/app/corpora/evil/paths.txt')
    assert clean_file.is_file(), f'Clean corpus missing at {clean_file}'
    assert evil_file.is_file(), f'Evil corpus missing at {evil_file}'

    clean_paths = clean_file.read_text(encoding='utf-8').splitlines()
    evil_paths = evil_file.read_text(encoding='utf-8').splitlines()

    clean_failures = []
    for path in clean_paths:
        try:
            if not is_safe(path):
                clean_failures.append(path)
        except Exception as exc:
            pytest.fail(f'is_safe_backup_path raised on clean path {path!r}: {exc}')

    evil_failures = []
    for path in evil_paths:
        try:
            if path == '/mnt/backup_restores/short':
                # This corpus entry satisfies the written length rule; derive its answer from the rules.
                if is_safe(path) is not expected_safe(path):
                    evil_failures.append(path)
            elif is_safe(path):
                evil_failures.append(path)
        except Exception as exc:
            pytest.fail(f'is_safe_backup_path raised on evil path {path!r}: {exc}')

    errors = []
    if evil_failures:
        errors.append(f'{len(evil_failures)} evil paths misclassified: {evil_failures}')
    if clean_failures:
        errors.append(f'{len(clean_failures)} of {len(clean_paths)} clean paths rejected: {clean_failures}')
    if errors:
        pytest.fail(' | '.join(errors))

    generated = [
        PREFIX,
        PREFIX + 'a',
        PREFIX[:-1],
        PREFIX.upper() + 'valid',
        PREFIX + 'alpha beta',
        PREFIX + 'alpha\tbeta',
        PREFIX + 'alpha\nbeta',
        PREFIX + 'alpha\rbeta',
        PREFIX + 'alpha\vbeta',
        PREFIX + 'alpha\fbeta',
        PREFIX + 'alpha\u00a0beta',
        PREFIX + '../target',
        PREFIX + 'segment..name',
        PREFIX + '.hidden/name',
    ]
    for meta in FORBIDDEN:
        generated.append(PREFIX + 'left' + meta + 'right')

    rng = random.Random(0x5A17C0DE)
    alphabet = string.ascii_letters + string.digits + '_-.'
    for _ in range(80):
        segments = []
        for _ in range(rng.randint(1, 5)):
            segment = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 18)))
            while '..' in segment:
                segment = segment.replace('..', '._')
            segments.append(segment)
        clean = PREFIX + '/'.join(segments)
        generated.append(clean)

        pos = rng.randint(0, len(clean))
        generated.append(clean[:pos] + '..' + clean[pos:])
        generated.append(clean + rng.choice(list(FORBIDDEN)))
        generated.append(clean + rng.choice([' ', '\t', '\n', '\u2003']))
        generated.append('/srv/restore/' + '/'.join(segments))

    for path in generated:
        call_and_check(is_safe, path)


def test_generate_restore_report_exists_and_imports_dependencies():
    report_file = Path('/home/user/generate_restore_report.py')
    assert report_file.is_file(), f'File {report_file} is missing'
    source = report_file.read_text(encoding='utf-8')
    tree = ast.parse(source, filename=str(report_file))

    imported_roots = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_roots.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported_roots.add(node.module.split('.')[0])

    assert 'path_checker' in imported_roots, 'generate_restore_report.py does not import path_checker'
    assert 'mail_sender' in imported_roots, 'generate_restore_report.py does not import mail_sender'
    compile(source, str(report_file), 'exec')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
