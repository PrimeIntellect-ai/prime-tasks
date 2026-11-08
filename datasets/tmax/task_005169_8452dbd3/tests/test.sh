#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the setup server if the agent left it running so the verifier can provide
# an independently generated stream on the required port.
pkill -f '^python3 /home/user/build_server.py' 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import os
import re
import secrets
import shutil
import stat
from pathlib import Path


def test_linker_flags_file_exists():
    assert os.path.isfile("/home/user/linker_flags.txt"), "The /home/user/linker_flags.txt file is missing."


def test_linker_flags_content():
    expected_lines = [
        "/home/user/libs/libcore.so.1.2.0",
        "/home/user/libs/libmath.so.3.1.4",
        "/home/user/libs/libnet.so.1.2.4"
    ]

    with open("/home/user/linker_flags.txt", "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of /home/user/linker_flags.txt do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def _version(value):
    parts = value.split(".")
    assert len(parts) == 3 and all(part.isdigit() for part in parts)
    return tuple(map(int, parts))


def _atom_matches(version, atom):
    match = re.fullmatch(r"(lib[A-Za-z0-9_]+)\s*(==|!=|>=|<=|>|<)\s*(\d+\.\d+\.\d+)", atom.strip())
    assert match, f"Invalid verifier constraint atom: {atom}"
    wanted = _version(match.group(3))
    op = match.group(2)
    return {
        "==": version == wanted,
        "!=": version != wanted,
        ">=": version >= wanted,
        "<=": version <= wanted,
        ">": version > wanted,
        "<": version < wanted,
    }[op]


def _expression_matches(version, expression):
    return any(
        all(_atom_matches(version, atom) for atom in and_group.split(" AND "))
        for and_group in expression.split(" OR ")
    )


def _expected_paths(library_versions, constraints):
    selected = []
    for library in sorted(constraints):
        valid = [
            version for version in library_versions[library]
            if all(_expression_matches(version, expression) for expression in constraints[library])
        ]
        assert valid, f"Verifier generated no solution for {library}"
        chosen = max(valid)
        selected.append(f"/home/user/libs/{library}.so.{chosen[0]}.{chosen[1]}.{chosen[2]}")
    return selected


def test_solver_executes_against_websocket_and_solves_generated_stream():
    solver = Path("/home/user/solver.py")
    assert solver.exists(), "The required /home/user/solver.py is missing."
    assert stat.S_ISREG(solver.stat().st_mode), "/home/user/solver.py must be a regular file."
    assert solver.stat().st_size > 0, "/home/user/solver.py is empty."

    base = 5 + secrets.randbelow(30)
    library_versions = {
        "libcore": [(base, 0, 0), (base, 4, 2), (base, 8, 3), (base + 1, 0, 0)],
        "libnet": [(base + 2, 1, 0), (base + 2, 5, 0), (base + 3, 0, 0)],
        "libmath": [(base + 4, 0, 1), (base + 4, 1, 4), (base + 4, 2, 0)],
    }
    constraints = {
        "libcore": [
            f"libcore >= {base}.0.0 AND libcore < {base + 1}.0.0",
            f"libcore != {base}.8.3",
        ],
        "libnet": [
            f"libnet == {base + 2}.1.0 OR libnet >= {base + 2}.5.0",
            f"libnet < {base + 3}.0.0",
        ],
        "libmath": [
            f"libmath > {base + 4}.0.1",
            f"libmath <= {base + 4}.1.4",
        ],
    }
    logs = [
        "[START BUILD] verifier_target",
        "[ANALYZE] empty_module",
        "[ANALYZE] generated_core_module",
        f"[DEPENDENCY] {constraints['libcore'][0]}",
        "[ANALYZE] generated_network_module",
        f"[DEPENDENCY] {constraints['libnet'][0]}",
        f"[DEPENDENCY] {constraints['libcore'][1]}",
        "[ANALYZE] generated_math_module",
        f"[DEPENDENCY] {constraints['libmath'][0]}",
        f"[DEPENDENCY] {constraints['net'][1]}" if 'net' in constraints else f"[DEPENDENCY] {constraints['libnet'][1]}",
        f"[DEPENDENCY] {constraints['libmath'][1]}",
        "[END BUILD]",
    ]
    expected = _expected_paths(library_versions, constraints)

    libs = Path("/home/user/libs")
    backup = Path(f"/home/user/libs.verifier-backup-{os.getpid()}")
    output = Path("/home/user/linker_flags.txt")
    old_output = output.read_bytes() if output.exists() else None

    assert libs.is_dir(), "/home/user/libs must be a directory."
    libs.rename(backup)
    libs.mkdir()
    for library, versions in library_versions.items():
        for version in versions:
            (libs / f"{library}.so.{version[0]}.{version[1]}.{version[2]}").touch()

    async def exercise():
        from websockets.legacy.server import serve

        connected = asyncio.Event()
        finished = asyncio.Event()
        graceful = {"value": False}

        async def handler(websocket, path):
            connected.set()
            try:
                for line in logs:
                    await websocket.send(line)
                    await asyncio.sleep(0.01)
                await asyncio.wait_for(websocket.wait_closed(), timeout=3)
                graceful["value"] = websocket.close_code == 1000
            finally:
                if not websocket.closed:
                    await websocket.close()
                finished.set()

        async with serve(handler, "localhost", 8080):
            process = await asyncio.create_subprocess_exec(
                "python3", str(solver),
                cwd="/home/user",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            try:
                stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=12)
            except asyncio.TimeoutError:
                process.kill()
                await process.communicate()
                raise AssertionError("solver.py did not finish after receiving [END BUILD]")

            assert process.returncode == 0, (
                f"solver.py exited with status {process.returncode}\n"
                f"stdout:\n{stdout.decode(errors='replace')}\n"
                f"stderr:\n{stderr.decode(errors='replace')}"
            )
            assert connected.is_set(), "solver.py did not connect to the WebSocket server."
            try:
                await asyncio.wait_for(finished.wait(), timeout=4)
            except asyncio.TimeoutError:
                raise AssertionError("solver.py did not close its WebSocket connection after [END BUILD]")
            assert graceful["value"], "solver.py did not gracefully close the WebSocket connection."

    try:
        asyncio.run(exercise())
        assert output.is_file(), "solver.py did not create /home/user/linker_flags.txt."
        actual = [line.strip() for line in output.read_text().splitlines() if line.strip()]
        assert actual == expected, (
            "solver.py produced an incorrect result for the verifier-generated stream.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
    finally:
        shutil.rmtree(libs, ignore_errors=True)
        backup.rename(libs)
        if old_output is None:
            output.unlink(missing_ok=True)
        else:
            output.write_bytes(old_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
