# openai/math challenge `MatchingAffineLift` (family 126)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 126 of the release, *Exponential semidefinite complexity of perfect matching*
(Theoretical computer science). The family as a whole: Proves that every exact semidefinite lift of the perfect matching polytope has exponential size, answering Rothvoss's polynomial-size lift question negatively. The bound holds even for the positive semidefinite rank of its odd-cut slack matrix after any fixed shift $0<\rho<1$, allowing arbitrary real positive semidefinite factors.

The challenge is `MatchingAffineLift`, also at `/opt/openai-math/challenges/MatchingAffineLift.lean`:

```lean
import Mathlib

namespace OAI

namespace PerfectMatchingPSD

abbrev Edge (n : ℕ) := {p : Fin n × Fin n // p.1 < p.2}

def IsPerfectMatching {n : ℕ} (M : Finset (Edge n)) : Prop :=
  ∀ v : Fin n, (M.filter fun e => e.1.1 = v ∨ e.1.2 = v).card = 1

abbrev PerfectMatching (n : ℕ) :=
  {M : Finset (Edge n) // IsPerfectMatching M}

noncomputable def matchingPoint {n : ℕ} (M : PerfectMatching n) : Edge n → ℝ := by
  classical
  exact fun e => if e ∈ M.1 then 1 else 0

noncomputable def matchingPolytope (n : ℕ) : Set (Edge n → ℝ) :=
  convexHull ℝ (Set.range (matchingPoint (n := n)))

def HasAffineLift (n r : ℕ) : Prop :=
  ∃ (L : AffineSubspace ℝ (Matrix (Fin r) (Fin r) ℝ))
    (T : Matrix (Fin r) (Fin r) ℝ →ᵃ[ℝ] (Edge n → ℝ)),
    T '' {X | X ∈ L ∧ X.PosSemidef} = matchingPolytope n

theorem affine_lift_lower_bound :
    ∀ C : ℝ, 0 < C → ∃ n₀ : ℕ, 4 ≤ n₀ ∧
      ∀ n : ℕ, n₀ ≤ n → Even n → ∀ r : ℕ,
        HasAffineLift n r → (n : ℝ) ^ C < (r : ℝ) := by
  sorry

end PerfectMatchingPSD

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MatchingAffineLift.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PerfectMatchingPSD.affine_lift_lower_bound` must keep exactly the statement shown above: same names,
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
