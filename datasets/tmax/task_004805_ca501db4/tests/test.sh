#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import ast
import configparser
import csv
import json
import os
import secrets
import shutil
import subprocess
import tempfile

BASE_DIR = "/home/user/locales"
UPDATES_DIR = os.path.join(BASE_DIR, "updates")
OUTPUT_DIR = os.path.join(BASE_DIR, "output")
BASE_JSON_PATH = os.path.join(BASE_DIR, "base.json")
FINAL_JSON_PATH = os.path.join(OUTPUT_DIR, "final.json")
SCRIPT_PATH = "/home/user/process_locales.py"

EXPECTED_DATA = {
    "de": {
        "btn_cancel": "Abbrechen_new",
        "btn_submit": "Einreichen",
        "lbl_error": "Fehler",
        "msg_goodbye": "Auf Wiedersehen",
        "msg_welcome": "Willkommen"
    },
    "en": {
        "btn_cancel": "Cancel",
        "lbl_error": "Error",
        "msg_goodbye": "Goodbye",
        "msg_welcome": "Welcome"
    },
    "es": {
        "btn_cancel": "Cancelar_new",
        "btn_submit": "Enviar",
        "lbl_error": "Error",
        "msg_goodbye": "Adiós",
        "msg_welcome": "Bienvenido"
    },
    "fr": {
        "btn_cancel": "Annuler_new",
        "btn_submit": "Soumettre",
        "lbl_error": "Erreur",
        "msg_goodbye": "Au revoir",
        "msg_welcome": "Bienvenue"
    }
}

assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
    tree = ast.parse(f.read(), filename=SCRIPT_PATH)

imports = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            imports.add(alias.name)
    elif isinstance(node, ast.ImportFrom) and node.module:
        imports.add(node.module)
assert "multiprocessing" in imports or "concurrent.futures" in imports, \
    "Script does not import 'multiprocessing' or 'concurrent.futures'."

instrument_dir = tempfile.mkdtemp(prefix="parallel_check_")
marker_path = os.path.join(instrument_dir, "parallel-used")
sitecustomize = r'''
import os
_MARKER = os.environ.get("LOCALE_PARALLEL_MARKER")
def _mark():
    if _MARKER:
        try:
            fd = os.open(_MARKER, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
            os.write(fd, b"used\n")
            os.close(fd)
        except Exception:
            pass
try:
    import multiprocessing.process as _mpprocess
    _original_start = _mpprocess.BaseProcess.start
    def _tracked_start(self, *args, **kwargs):
        _mark()
        return _original_start(self, *args, **kwargs)
    _mpprocess.BaseProcess.start = _tracked_start
except Exception:
    pass
try:
    import multiprocessing.pool as _mppool
    _OriginalPool = _mppool.Pool
    class _TrackingPool(_OriginalPool):
        def __init__(self, *args, **kwargs):
            _mark()
            super().__init__(*args, **kwargs)
    _mppool.Pool = _TrackingPool
except Exception:
    pass
try:
    import concurrent.futures as _cf
    import concurrent.futures.thread as _cft
    _OriginalThreadPoolExecutor = _cft.ThreadPoolExecutor
    class _TrackingThreadPoolExecutor(_OriginalThreadPoolExecutor):
        def __init__(self, *args, **kwargs):
            _mark()
            super().__init__(*args, **kwargs)
    _cft.ThreadPoolExecutor = _TrackingThreadPoolExecutor
    _cf.ThreadPoolExecutor = _TrackingThreadPoolExecutor
except Exception:
    pass
try:
    import concurrent.futures as _cf
    import concurrent.futures.process as _cfp
    _OriginalProcessPoolExecutor = _cfp.ProcessPoolExecutor
    class _TrackingProcessPoolExecutor(_OriginalProcessPoolExecutor):
        def __init__(self, *args, **kwargs):
            _mark()
            super().__init__(*args, **kwargs)
    _cfp.ProcessPoolExecutor = _TrackingProcessPoolExecutor
    _cf.ProcessPoolExecutor = _TrackingProcessPoolExecutor
except Exception:
    pass
'''
with open(os.path.join(instrument_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
    f.write(sitecustomize)

def clear_output():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name in os.listdir(OUTPUT_DIR):
        path = os.path.join(OUTPUT_DIR, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

def run_script():
    if os.path.exists(marker_path):
        os.unlink(marker_path)
    env = os.environ.copy()
    env["LOCALE_PARALLEL_MARKER"] = marker_path
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = instrument_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, \
        f"Script execution failed with status {result.returncode}:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(marker_path) and os.path.getsize(marker_path) > 0, \
        "The script did not actually create or start a multiprocessing/concurrent.futures worker or executor."

def load_json_and_check_format(expected):
    assert os.path.isfile(FINAL_JSON_PATH), f"File {FINAL_JSON_PATH} does not exist."
    with open(FINAL_JSON_PATH, "r", encoding="utf-8") as f:
        text = f.read()
    data = json.loads(text)
    assert data == expected, f"Exact merged JSON content is incorrect. Expected {expected!r}, got {data!r}."

    def ordered_object(pairs):
        keys = [key for key, _ in pairs]
        assert keys == sorted(keys), f"JSON object keys are not sorted alphabetically: {keys!r}"
        return dict(pairs)
    json.loads(text, object_pairs_hook=ordered_object)

    normalized = text[:-1] if text.endswith("\n") else text
    allowed = {
        json.dumps(data, indent=2, sort_keys=True, ensure_ascii=True),
        json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False),
    }
    assert normalized in allowed, "final.json is not formatted with exactly 2-space indentation and sorted keys."

def check_ini_files(expected):
    expected_locales = sorted(locale for locale in expected if locale != "en")
    actual_ini_names = sorted(
        name for name in os.listdir(OUTPUT_DIR)
        if name.startswith("final_") and name.endswith(".ini")
    )
    expected_ini_names = [f"final_{locale}.ini" for locale in expected_locales]
    assert actual_ini_names == expected_ini_names, \
        f"Expected INI files {expected_ini_names!r}, got {actual_ini_names!r}."
    assert not os.path.exists(os.path.join(OUTPUT_DIR, "final_en.ini")), \
        "English INI file should not be generated."

    for locale in expected_locales:
        ini_path = os.path.join(OUTPUT_DIR, f"final_{locale}.ini")
        assert os.path.isfile(ini_path), f"INI file {ini_path} does not exist."
        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str
        with open(ini_path, "r", encoding="utf-8") as f:
            config.read_file(f)
        assert config.sections() == ["translations"], \
            f"{ini_path} must contain exactly one [translations] section."
        actual = dict(config["translations"])
        assert actual == expected[locale], \
            f"Exact INI content for locale {locale!r} is incorrect: {actual!r}."

        with open(ini_path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
        expected_lines = ["[translations]"] + [
            f"{key}={expected[locale][key]}" for key in sorted(expected[locale])
        ]
        assert lines == expected_lines, \
            f"{ini_path} must have one section and alphabetically sorted key=value lines."

# Execute against the supplied fixtures and retain the original content checks,
# strengthened to require exact JSON and all locale output.
clear_output()
run_script()
load_json_and_check_format(EXPECTED_DATA)
check_ini_files(EXPECTED_DATA)

# Replace the fixtures with unpredictable data, execute the submitted artifact
# again, and derive the complete expected merge from those generated inputs.
token = secrets.token_hex(8)
shutil.rmtree(UPDATES_DIR)
os.makedirs(UPDATES_DIR)
base = {
    "de": {"base_only_" + token: "Grundlage " + token, "overwrite_" + token: "alt-de"},
    "es": {"base_only_" + token: "Base " + token, "overwrite_" + token: "old-es"},
    "fr": {"base_only_" + token: "Fondation " + token, "overwrite_" + token: "vieux-fr"},
}
with open(BASE_JSON_PATH, "w", encoding="utf-8") as f:
    json.dump(base, f)

rows_by_file = {
    "zeta_" + token + ".csv": [
        ["string_id", "en", "es", "fr", "de"],
        ["welcome_" + token, "Welcome " + token, "Bienvenido, " + token, "Bienvenue " + token, "Willkommen " + token],
    ],
    "alpha_" + token + ".csv": [
        ["string_id", "en", "es", "fr", "de"],
        ["overwrite_" + token, "Fresh " + token, "nuevo " + token, "nouveau " + token, "neu " + token],
        ["quoted_" + token, 'Say "hello" ' + token, 'Dice "hola" ' + token, 'Dit "salut" ' + token, 'Sagt "hallo" ' + token],
    ],
    "middle_" + token + ".csv": [
        ["string_id", "en", "es", "fr", "de"],
        ["goodbye_" + token, "Goodbye " + token, "Adiós " + token, "Au revoir " + token, "Auf Wiedersehen " + token],
    ],
}
for filename, rows in rows_by_file.items():
    with open(os.path.join(UPDATES_DIR, filename), "w", encoding="utf-8", newline="") as f:
        csv.writer(f).writerows(rows)

expected_dynamic = {locale: translations.copy() for locale, translations in base.items()}
for rows in rows_by_file.values():
    header = rows[0]
    for row in rows[1:]:
        string_id = row[0]
        for index, locale in enumerate(header[1:], 1):
            expected_dynamic.setdefault(locale, {})[string_id] = row[index]

clear_output()
run_script()
load_json_and_check_format(expected_dynamic)
check_ini_files(expected_dynamic)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
