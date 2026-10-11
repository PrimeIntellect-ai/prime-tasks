# openai/math challenge `CliqueFreeLog` (family 184)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 184 of the release, *Coloring and independence in graphs with forbidden subgraphs*
(Combinatorics). The family as a whole: Proves the Alon–Krivelevich–Sudakov coloring conjecture in correspondence-coloring form: graphs avoiding any fixed subgraph $F$ need $O_F(\Delta/\log\Delta)$ colors when their maximum degree $\Delta$ is sufficiently large. Also proves the Ajtai–Erd\H{o}s–Komlos–Szemeredi independence conjecture: for fixed $r\ge4$, every $n$-vertex $K_r$-free graph of average degree $d\ge2$ has an independent set of size $\Omega_r(n\log d/d)$.

The challenge is `CliqueFreeLog`, also at `/opt/openai-math/challenges/CliqueFreeLog.lean`:

```lean
import Mathlib

namespace OAI

namespace CliqueFreeLog

noncomputable def averageDegree {V : Type*} [Fintype V] (G : SimpleGraph V) : ℝ := by
  classical
  exact 2 * (G.edgeFinset.card : ℝ) / (Fintype.card V : ℝ)

theorem logarithmic_independence_bound (r : ℕ) (hr : 4 ≤ r) :
    ∃ c : ℝ, 0 < c ∧
      ∀ {V : Type} [Fintype V] (G : SimpleGraph V),
        G.CliqueFree r → 2 ≤ averageDegree G →
        c * (Fintype.card V : ℝ) * Real.log (averageDegree G) / averageDegree G ≤
          (G.indepNum : ℝ) := by
  sorry

end CliqueFreeLog

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CliqueFreeLog.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CliqueFreeLog.logarithmic_independence_bound` must keep exactly the statement shown above: same names,
  namespaces, binders and types. Every definition the statements use must stay exactly as written.
  Change nothing except the proofs.
- **Standard axioms only.** Proofs may use only `propext`, `Quot.sound` and `Classical.choice`.
  `sorry`, `admit`, new `axiom`s and `native_decide` (it introduces an axiom of its own) are rejected.
- **Keep the challenge's declarations as they are.** Put new lemmas and instances *after* the
  definitions the statements use, or in a separate `Submission/*.lean` module. A declaration added
  before them can change how they elaborate, and then they no longer match the challenge.
- **Kernel-checked.** The proofs are re-checked by the Lean kernel, not just the elaborator.

Long proofs can be split into modules under `/workspace/Submission/` (module names
`Submission.Foo`, `Submission.Foo.Bar`) imported from `Submission.lean`. Only `.lean` files at
those two paths are graded.

## Environment

- Lean `v4.34.1` and Mathlib at commit `d13f23b` are installed and prebuilt; `/workspace` is a
  Lake project.
- The sandbox has 4 CPUs and 8 GB of memory; `LEAN_NUM_THREADS=3` keeps `lake build` to three
  parallel jobs. Check your work with `cd /workspace && lake build Submission`. Add `#print axioms <name>` to see
  which axioms a proof uses.
- There is no internet access. OpenAI's own proofs are not installed.

## Grading

When you finish, `Submission.lean` and `Submission/**.lean` are copied to a fresh machine and
checked with [Comparator](https://github.com/leanprover/comparator), the Lean FRO's proof checker.
The reward is 1 if Comparator accepts the proof and 0 otherwise. A partial proof scores 0.
