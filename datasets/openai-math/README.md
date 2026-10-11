---
license: apache-2.0
task_categories:
- other
tags:
- harbor
- rl-environment
- reinforcement-learning
- code-agent
- lean4
- mathlib
- theorem-proving
- openai-math
pretty_name: "openai/math as Harbor environments"
---

# openai/math as Harbor environments

> **Experimental.** Built on a research release that is itself new and not yet independently
> reviewed. Expect rough edges, and read any proof that scores 1 before relying on it.

## Prime Intellect import

Mirrored from [FineEnvs/openai-math](https://huggingface.co/datasets/FineEnvs/openai-math) at
revision `d7056fd31c19fd1a0aed0a0bc3e99026d412b2ca`; the first commit adding this directory is a
byte-identical copy. The `openai-math` taskset in
[`prime-envs`](https://github.com/PrimeIntellect-ai/prime-envs) runs these tasks on Prime VM
sandboxes instead of Daytona. The changes below are made identically in `generator/` and in every
task. Statements, Comparator configs, permitted axioms, resources, timeouts and the reward are
unchanged.

- **Image.** Each `task.toml` declares the prebuilt image
  `prime/primeintellect/openai-math:adc7f12-d7056fd-prime1`, built from `environment/`, because
  Verifiers does not build Dockerfiles.
- **Build sandbox.** Prime VM guests have no Landlock LSM, so landrun's `--best-effort` mode would
  run Comparator's builds unconfined. They also have no Yama, so such a build could ptrace
  Comparator itself. `environment/landrun_bwrap.py`, installed as `/usr/local/bin/landrun-bwrap`
  in a final image layer alongside `bubblewrap` and `nftables`, accepts the landrun arguments
  Comparator passes and applies the same policy with bubblewrap:
  - read-only `/`,
  - writable `.lake` only,
  - no network,
  - fresh user and PID namespaces.

  landrun's executable allow-list has no bubblewrap equivalent and is not reproduced, so a build
  can execute a shell. It still cannot write outside `.lake`, open connections, or see processes
  outside the sandbox. `tests/grade.py` points Comparator at the shim through
  `COMPARATOR_LANDRUN`, and `check_build_sandbox` verifies the shim before every grading.
- **Network block.** Prime guests cannot load the iptables `owner` match, so upstream's rule fails
  and grading would always error. `tests/grade.py` installs the equivalent nftables rule
  (`meta skuid grader reject`). It probes the rule with a loopback listener it opens itself,
  rather than Daytona's in-sandbox service on port 2280.
- **Open files.** Prime guests start with a system-wide limit of about 98k open files, which a
  parallel Lean build exhausts. `tests/grade.py` raises `fs.file-max` to 2^20, as the
  `prime-envs` taskset does in the agent's sandbox.
- **Disk.** Prime counts the image (about 9.2 GB) toward a sandbox's disk, while Daytona's 10 GB
  is working space on top of it. The `prime-envs` taskset adds the image size to `storage_mb`.

To rebuild the image, use a builder with more than 4 GB of memory; the Lean builds in
`lean_setup.sh` were killed in 4 GB VMs:

```bash
uv run prime images push openai-math:adc7f12-d7056fd-prime1 --context generator/image
```

`scripts/openai-math/validate.py` re-runs the gold (official proof), empty and adversarial
controls through Verifiers' separate-verifier lifecycle on Prime.

We ported the math problems from OpenAI's [openai/math](https://github.com/openai/math) release
(commit `adc7f12`) into [Harbor](https://github.com/harbor-framework/harbor) environments.
The release formalizes **405** of its results as Lean statements. This dataset contains
**369 environments**, the ones whose official proof we verified end to end in the environment,
covering 214 result families across 17 fields. The other 36 are listed
under [Validation](#validation) with the reason each could not be validated.

## How a task works

The agent gets a sandbox with Lean 4 and a prebuilt Mathlib, no internet, and one of OpenAI's
theorems written in Lean with `sorry` where the proof should be.

**What `sorry` means.** In Lean, `sorry` is a placeholder for a missing proof: it lets the file
compile as if the step were proven, but nothing has actually been shown, and Lean flags it. The
statement is given exactly as OpenAI formalized it, and the agent's job is to replace every `sorry`
with a real proof.

When the agent finishes, a separate, fresh sandbox checks its proof with
[Comparator](https://github.com/leanprover/comparator), the Lean FRO's proof checker:

- **reward 1** if the theorem has exactly the original statement, the proof uses only Lean's
  standard axioms (`propext`, `Quot.sound`, `Classical.choice`, so no leftover `sorry` and no new
  axioms), and the Lean kernel accepts it;
- **reward 0** otherwise.

OpenAI's own proofs serve as the reference solutions: Harbor's oracle fetches them from GitHub at
run time. They are not included here and the agent never sees them.

## A strict reward

The grader only accepts a complete proof of the statement exactly as OpenAI formalized it. That
makes it hard to game, but it is also a real limitation for problems like these:

- a correct proof of an equivalent statement, written with different definitions or a different
  formulation, scores 0;
- partial progress (useful lemmas, a proof of a special case, a correct strategy with a gap) scores 0;
- nothing rewards a creative approach unless it ends in a complete proof of this exact statement.

For open research problems, a more general reward function that recognizes any valid solution to the
underlying problem, including creative reformulations and partial progress, would be a better
training signal. We use the strict check here because it is precise and cannot be fooled; treat it
as one end of that design space.

## What's included

- `tasks/` — one Harbor task per validated problem: instruction, Lean statement, sandbox image recipe,
  verifier and oracle
- `registry.json` — Harbor registry entry (`openai-math@1.0`)
- `manifest.parquet` — one row per task: field, family, theorem names, reference-proof size, oracle
  result
- `generator/` — the code that builds the sandbox image and regenerates the tasks from openai/math
- `LICENSE`, `NOTICE`, `LICENSE-openai-math` — licensing and attribution

## Run it with the Harbor CLI

You need Harbor 0.24+ with the Daytona backend (`DAYTONA_API_KEY`, `DAYTONA_API_URL`) and
credentials for the agent you run.

```bash
pip install "harbor[daytona]>=0.24" daytona
hf download FineEnvs/openai-math --repo-type dataset --local-dir openai-math
cd openai-math

# Build the shared sandbox image once (Lean 4, Mathlib, Comparator; ~9 GB, about an hour).
(cd generator && python -m openai_math_harbor.snapshot)
SNAP=$(cd generator && python -m openai_math_harbor.snapshot --print-name)

# Run any agent Harbor supports (`harbor agent list`) on a few tasks:
harbor run -p tasks -e daytona --ek snapshot_template_name=$SNAP \
  -a <agent> -m <model> -i plane-coloring -i hilbert-crouzeix -n 2

# Check that the grader accepts OpenAI's own proof of a task:
harbor run -p tasks -e daytona --ek snapshot_template_name=$SNAP \
  -a oracle --allow-agent-host github.com -i plane-coloring
```

Each task asks for 4 CPUs, 8 GB of memory and 10 GB of disk, and gives the agent 4 hours. Task
names are the folder names under `tasks/`.

## Validation

We generated a task for every statement except one left out by design (`DefocusingNLS`, whose
statement has a `sorry` inside a definition its theorems depend on), and ran Harbor's oracle on each:
it submits OpenAI's own proof and has it graded by the same verifier an agent faces. Only tasks whose
official proof was accepted are included.

| Oracle result | Tasks | Meaning |
|---|---|---|
| accepted | 369 | OpenAI's proof is accepted: the environment is verified end to end |
| missing-package | 21 | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| definition-mismatch | 2 | OpenAI's proof writes a definition with the same text but it compiles differently, so the exact-match check fails |
| memory | 10 | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| not completed | 2 | grading did not complete in our run |

Grading an accepted proof took 8 minutes at the median. Each task's result is in its `task.toml` (`oracle_result`) and in `manifest.parquet`.

<details><summary>36 statements not included (click to expand)</summary>

| Statement | Why it could not be validated |
|---|---|
| `arnold-counterexample` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `catalan` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `coarse-assembly` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `continuum-coulomb-hardness` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `cycle-clique-ramsey` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `defocusing-nls` | left out by design: OAI.DefocusingNLS.sobolevProduct: open definition the theorem statements depend on |
| `dirichlet-seven-eighths` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `duke-prime-degree` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `einstein-four` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `erdos-reciprocal` | grading did not complete in our run |
| `hecke-seven-eighths` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `jacobsthal` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `jacobsthal-improved` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `joint-dickman` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `koebe-circle-domains` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `matrix-multiplication` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `mub-six` | grading did not complete in our run |
| `nuclear-ultrapower` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `occupied-overlap` | OpenAI's proof writes a definition with the same text but it compiles differently, so the exact-match check fails |
| `ordinary-two-point-correlations` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `ostmann-complete` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `ostmann-primes` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `patterson-first-moment` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `planar-packing` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `polycyclic-recognition` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `quasi-riemann-hypothesis` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `riesz-quantitative` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `siegel-zeros` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `snaky-certificate` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `snaky-twenty-one` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `spin-angle` | OpenAI's proof writes a definition with the same text but it compiles differently, so the exact-match check fails |
| `surface-immersion` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `taming-compatibility` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |
| `totient-asymptotic` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `totient-companion-zero` | OpenAI's proof uses a Lean library beyond Mathlib that the sandbox does not include |
| `universal-tensor-squares` | OpenAI's proof needs more than the sandbox's 8 GB of memory to build |

</details>

The verifier was also tested against submissions that try to cheat (`sorry` in several disguises,
fake axioms, `native_decide`, weakened statements, redefined definitions, planted reward files, code
that runs during grading, a build that fills the verifier's disk). All scored 0. A no-op agent scores 0.

## Notes

- **Configs.** In eight of openai/math's Comparator configs, definitions written out in the statement
  were listed as "holes" that Comparator does not check, so a solution could redefine them. Here they
  must match exactly; affected tasks list them under `fixed_definitions` in `task.toml`.
- **Contamination.** The statements and proofs have been public since 6 October 2026.
- **Difficulty.** These are open research problems; expect reward 0 on almost every task.

Technical details (grading design, threat model, image recipe) are in `generator/README.md`.

## License

- The Lean statements are copied unchanged from [openai/math](https://github.com/openai/math)
  (© OpenAI), licensed under the
  [Apache License 2.0](https://github.com/openai/math/blob/main/LICENSE); see `LICENSE-openai-math`
  and `NOTICE`. OpenAI's proofs are not redistributed.
- The packaging, verifier and generator are Apache-2.0 (`LICENSE`).
- The sandbox image is built from [Lean 4](https://github.com/leanprover/lean4) and
  [Mathlib](https://github.com/leanprover-community/mathlib4) (Apache-2.0),
  [Comparator](https://github.com/leanprover/comparator) and
  [lean4export](https://github.com/leanprover/lean4export) (Apache-2.0), and
  [landrun](https://github.com/Zouuup/landrun) (MIT).
- If you use the results, cite the openai/math manuscripts as that repository asks.
