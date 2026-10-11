# openai/math challenge `SingleLatticeCovering` (family 092)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 092 of the release, *The optimal order of convex-body covering density*
(Convex and metric geometry). The family as a whole: Determines the optimal worst-case covering density as $\Theta(n\log n)$, for both lattice and unrestricted translative coverings. Every convex body in $\mathbb R^n$, $n\ge2$, admits a lattice covering of density at most $Cn\log n$; centrally symmetric examples in every sufficiently large dimension require at least $cn\log n$ even without the lattice restriction, for absolute $c,C>0$.

The challenge is `SingleLatticeCovering`, also at `/opt/openai-math/challenges/SingleLatticeCovering.lean`:

```lean
import Mathlib

namespace OAI

/-! Convex bodies and exact coverings by a single lattice in real coordinate space. -/

namespace SingleLatticeCovering

open MeasureTheory
open scoped Pointwise

abbrev Space (n : ℕ) := Fin n → ℝ

def IsConvexBody {n : ℕ} (K : Set (Space n)) : Prop :=
  IsCompact K ∧ Convex ℝ K ∧ (interior K).Nonempty

def LatticeCovers {n : ℕ} (K : Set (Space n)) (L : Submodule ℤ (Space n)) : Prop :=
  K + (L : Set (Space n)) = Set.univ

theorem single_lattice_covering :
    ∃ C : ℝ, 0 < C ∧ ∀ (n : ℕ), 2 ≤ n →
      ∀ (K : Set (Space n)), IsConvexBody K →
        ∃ (L : Submodule ℤ (Space n)) (_ : DiscreteTopology L),
          IsZLattice ℝ L ∧ LatticeCovers K L ∧
            (volume K).toReal / ZLattice.covolume L ≤ C * (n : ℝ) * Real.log (n : ℝ) := by sorry

end SingleLatticeCovering

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SingleLatticeCovering.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SingleLatticeCovering.single_lattice_covering` must keep exactly the statement shown above: same names,
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
