"""Model-free author QC through VF's native, separate-verifier Harbor lifecycle.

Run with a VF checkout that supports confined artifact links. This executes the
trusted solution/solve.sh control; ProgramBench's shipped solution reconstructs
the reference executable, rather than compiling the original project source.
"""

import argparse
import asyncio
import hashlib
import io
import json
import logging
import time
import traceback
from pathlib import Path
from tarfile import DIRTYPE, TarInfo
from tarfile import open as tar_open

from check_oracle import check

import verifiers.v1 as vf
from verifiers.v1.runtimes import provision_runtime
from verifiers.v1.tasksets.harbor.env import HarborEnv, HarborEnvConfig
from verifiers.v1.tasksets.harbor.taskset import HarborConfig, HarborTask, parse_task
from verifiers.v1.trace import AgentInfo, TraceTask
from verifiers.v1.utils.compile import resolve_runtime_config

LOGS = (
    "programbench_eval.json",
    "harbor_diagnostics.json",
    "reward.json",
    "programbench_eval.log",
)
PROBE = "/workspace/.qc-build-links"


def fingerprint(task: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(task.rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(task)).encode() + b"\0")
            digest.update(path.read_bytes())
    return digest.hexdigest()


def empty_workspace() -> bytes:
    buffer = io.BytesIO()
    with tar_open(fileobj=buffer, mode="w") as archive:
        member = TarInfo("workspace")
        member.type, member.mode = DIRTYPE, 0o755
        archive.addfile(member)
    return buffer.getvalue()


def check_control(
    path: Path, folder: Path, control: str, reward: float
) -> tuple[bool, dict]:
    qc = check(path, folder)
    if control == "gold":
        return reward == 1 and qc["oracle_pass"], qc
    return (
        reward == 0
        and qc["outputs_consistent"]
        and qc["n_expected"] > 0
        and qc["error_code"] == "missing_compile_sh"
        and qc["statuses"] == {"not_run": qc["n_expected"]}
        and not qc["branch_errors"],
        qc,
    )


async def validate(path: Path, index: int, control: str, output: Path) -> dict:
    folder = output / path.name / control
    fingerprint_value = fingerprint(path)
    previous = folder / "result.json"
    if previous.exists():
        try:
            old = json.loads(previous.read_text())
            if old.get("passed") and old.get("task_sha256") == fingerprint_value:
                passed, _ = check_control(path, folder, control, old["reward"])
                if passed:
                    return old
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            pass  # Preserve invalid cached evidence as a failed attempt below.
    if folder.exists():
        # Retain every failed or stale attempt, including its logs and VM IDs.
        folder.rename(folder.with_name(f"{control}-attempt-{time.time_ns()}"))
    folder.mkdir(parents=True)
    started = time.monotonic()
    record = {
        "task": path.name,
        "control": control,
        "task_sha256": fingerprint_value,
        "passed": False,
    }

    class QCTask(HarborTask):
        async def run_verifier(self, runtime, trace):
            record["verifier"] = runtime.info.model_dump(mode="json")
            (folder / "runtime.json").write_text(json.dumps(record, indent=2))
            assertion = "test ! -e /workspace/executable"
            if control == "gold":
                assertion += (
                    f" && test {PROBE}/object -ef {PROBE}/hardlink"
                    f" && test -L {PROBE}/relative-link"
                    f" && test {PROBE}/object -ef {PROBE}/relative-link"
                )
            else:
                assertion += " && test ! -e /workspace/compile.sh"
            result = await runtime.run(["sh", "-c", assertion], {})
            if result.exit_code:
                raise RuntimeError(
                    "fresh-verifier/reference-exclusion/artifact check failed"
                )
            if control == "gold":
                result = await runtime.run(["rm", "-rf", PROBE], {})
                if result.exit_code:
                    raise RuntimeError("artifact probe cleanup failed")
            try:
                return await super().run_verifier(runtime, trace)
            finally:
                for name in LOGS:
                    try:
                        (folder / name).write_bytes(
                            await runtime.read(
                                f"/logs/verifier/{name}", max_bytes=32 * 1024 * 1024
                            )
                        )
                    except Exception as exc:  # noqa: BLE001 - retain other logs after one read failure
                        (folder / f"{name}.read-error").write_text(str(exc))

    try:
        task = QCTask(
            parse_task(
                path,
                index,
                HarborConfig(
                    artifact_max_bytes=512 * 1024 * 1024, ignore_timeouts=False
                ),
            )
        )
        env = HarborEnv(
            HarborEnvConfig(
                taskset={"id": "harbor"},
                agent=vf.AgentConfig(
                    runtime=vf.PrimeConfig(labels=["programbench-author-qc"])
                ),
                verifier={"retries": 0},
            )
        )
        trace = vf.Trace(
            task=TraceTask(type="QCTask", data=task.data),
            agent=AgentInfo(config=env.config.agent),
            ok=True,
            is_completed=True,
        )
        async with asyncio.timeout(18000):
            if control == "gold":
                async with provision_runtime(
                    resolve_runtime_config(env.config.agent.runtime, task)
                ) as solver:
                    record["solver"] = solver.info.model_dump(mode="json")
                    await solver.prepare_setup()
                    trace.agent.runtime = solver.info
                    await task.setup(solver)
                    await solver.write(
                        "/tmp/qc-solve.sh", (path / "solution/solve.sh").read_bytes()
                    )
                    result = await solver.run(["bash", "/tmp/qc-solve.sh"], {})
                    if result.exit_code:
                        raise RuntimeError(
                            f"gold preparation failed: {result.stderr[-2000:]}"
                        )
                    result = await solver.run(
                        [
                            "sh",
                            "-c",
                            (
                                f"test ! -e {PROBE} && mkdir {PROBE} && printf object > {PROBE}/object"
                                f" && ln {PROBE}/object {PROBE}/hardlink"
                                f" && ln -s object {PROBE}/relative-link"
                            ),
                        ],
                        {},
                    )
                    if result.exit_code:
                        raise RuntimeError(
                            f"artifact probe setup failed: {result.stderr}"
                        )
                    await task.finalize(trace, solver)
            else:
                trace.state.artifacts["/workspace"] = empty_workspace()
            episode = vf.Episode(task=trace.task, traces=[trace])
            await env.finalize(task, episode)
        record["reward"] = episode.traces[0].rewards["reward"].score
        record["passed"], record["qc"] = check_control(
            path, folder, control, record["reward"]
        )
        if control == "empty":
            record["error_code"] = record["qc"]["error_code"]
        record["status"] = "passed" if record["passed"] else "control_failed"
    except Exception as exc:  # noqa: BLE001 - report each task failure without abandoning the batch
        record.update(status="execution_error", error=f"{type(exc).__name__}: {exc}")
        (folder / "exception.txt").write_text(traceback.format_exc())
    record["seconds"] = round(time.monotonic() - started, 2)
    (folder / "result.json").write_text(json.dumps(record, indent=2))
    print(
        json.dumps(
            {key: record[key] for key in ("task", "control", "status", "seconds")}
        ),
        flush=True,
    )
    return record


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dataset",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "datasets/programbench",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--task",
        action="append",
        default=[],
        help="Exact task directory name; repeat to select tasks",
    )
    parser.add_argument("--control", choices=("gold", "empty", "both"), default="both")
    parser.add_argument("--concurrency", type=int, default=4)
    args = parser.parse_args()
    if args.concurrency < 1:
        parser.error("--concurrency must be positive")
    tasks = sorted(path.parent for path in args.dataset.glob("*/task.toml"))
    if args.task:
        unknown = set(args.task) - {path.name for path in tasks}
        if unknown:
            parser.error(f"unknown tasks: {sorted(unknown)}")
        tasks = [path for path in tasks if path.name in args.task]
    if not tasks:
        parser.error("no tasks found")
    # Validate every selected TOML before any provisioning or charges.
    for index, path in enumerate(tasks):
        parse_task(path, index, HarborConfig(ignore_timeouts=False))
    controls = ("gold", "empty") if args.control == "both" else (args.control,)
    semaphore = asyncio.Semaphore(args.concurrency)

    async def run(path, index, control):
        async with semaphore:
            return await validate(path, index, control, args.output)

    results = await asyncio.gather(
        *(
            run(path, index, control)
            for index, path in enumerate(tasks)
            for control in controls
        )
    )
    report = {
        "expected": len(tasks) * len(controls),
        "passed": sum(result["passed"] for result in results),
        "results": results,
    }
    (args.output / "summary.json").write_text(json.dumps(report, indent=2))
    raise SystemExit(0 if all(result["passed"] for result in results) else 1)


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    asyncio.run(main())
