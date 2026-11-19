# openai/math challenge `KadisonRingrose` (family 295)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 295 of the release, *The Kadison–Ringrose cohomology conjecture*
(Operator algebras). The family as a whole: Proves that every bounded Hochschild cocycle of degree at least two on a complex von Neumann algebra, with coefficients in the algebra itself, has a bounded primitive. Equivalently, all higher bounded Hochschild cohomology groups vanish, resolving the Kadison–Ringrose conjecture.

The challenge is `KadisonRingrose`, also at `/opt/openai-math/challenges/KadisonRingrose.lean`:

```lean
import Mathlib

namespace OAI

/-! Every ordinary bounded higher Hochschild cocycle of a complex von Neumann
algebra is the coboundary of a bounded cochain with values in the same algebra. -/

noncomputable section

namespace BoundedHochschild

abbrev Cochain (M : Type*) [NormedAddCommGroup M] [NormedSpace ℂ M] (n : ℕ) :=
  ContinuousMultilinearMap ℂ (fun _ : Fin n => M) M

def mergeInputs {M : Type*} [Mul M] {n : ℕ}
    (v : Fin (n + 1) → M) (j : Fin n) : Fin n → M :=
  fun i => if i < j then v i.castSucc
    else if i = j then v i.castSucc * v i.succ else v i.succ

noncomputable def differentialValue {M : Type*} [NormedRing M] [NormedAlgebra ℂ M]
    {n : ℕ} (f : Cochain M n) (v : Fin (n + 1) → M) : M :=
  v 0 * f (fun i => v i.succ) +
    ∑ j : Fin n, ((-1 : ℂ) ^ (j.val + 1)) • f (mergeInputs v j) +
    ((-1 : ℂ) ^ (n + 1)) • (f (fun i => v i.castSucc) * v (Fin.last n))

namespace KadisonRingrose

universe u

theorem main_result
    {M : Type u} [CStarAlgebra M] [PartialOrder M] [StarOrderedRing M] [WStarAlgebra M]
    (n : ℕ) (f : Cochain M (n + 2))
    (hf : ∀ x : Fin (n + 3) → M, differentialValue f x = 0) :
    ∃ g : Cochain M (n + 1), ∀ x : Fin (n + 2) → M,
      differentialValue g x = f x := by
  sorry

end KadisonRingrose
end BoundedHochschild

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/KadisonRingrose.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.BoundedHochschild.KadisonRingrose.main_result` must keep exactly the statement shown above: same names,
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
