# openai/math challenge `PlanarUnitDistances` (family 167)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 167 of the release, *Pinned distances and a power saving for planar unit distances*
(Combinatorics). The family as a whole: Proves the weak pinned Erd\H{o}s distance conjecture: for every fixed $\varepsilon>0$, all but $o(n)$ points of any $n$-point planar set determine at least $n^{1-\varepsilon}$ distinct nonzero distances. A complementary theorem bounds the number of unit-distance pairs by $O(n^{4/3-\delta})$ for an absolute $\delta>0$.

The challenge is `PlanarUnitDistances`, also at `/opt/openai-math/challenges/PlanarUnitDistances.lean`:

```lean
import Mathlib

namespace OAI

namespace PlanarUnitDistances

abbrev Plane := EuclideanSpace ℝ (Fin 2)

def IsUnitPair : Sym2 Plane → Prop :=
  Sym2.lift ⟨fun x y => dist x y = 1, fun x y => by dsimp; rw [dist_comm]⟩

noncomputable def unitPairCount (X : Finset Plane) : ℕ := by
  classical
  exact (X.sym2.filter IsUnitPair).card

noncomputable def u (n : ℕ) : ℕ :=
  sSup {m : ℕ | ∃ X : Finset Plane, X.card = n ∧ unitPairCount X = m}

theorem main : ∃ C β : ℝ, 0 < C ∧ 1 ≤ β ∧ β < (4 : ℝ) / 3 ∧
    ∀ n : ℕ, (u n : ℝ) ≤ C * (n : ℝ) ^ β := by
  sorry

end PlanarUnitDistances

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PlanarUnitDistances.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PlanarUnitDistances.main` must keep exactly the statement shown above: same names,
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
