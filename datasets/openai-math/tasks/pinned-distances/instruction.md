# openai/math challenge `PinnedDistances` (family 167)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 167 of the release, *Pinned distances and a power saving for planar unit distances*
(Combinatorics). The family as a whole: Proves the weak pinned Erd\H{o}s distance conjecture: for every fixed $\varepsilon>0$, all but $o(n)$ points of any $n$-point planar set determine at least $n^{1-\varepsilon}$ distinct nonzero distances. A complementary theorem bounds the number of unit-distance pairs by $O(n^{4/3-\delta})$ for an absolute $\delta>0$.

The challenge is `PinnedDistances`, also at `/opt/openai-math/challenges/PinnedDistances.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open Filter
open scoped Topology

namespace WeakPinned
abbrev Plane := EuclideanSpace ℝ (Fin 2)

def distanceFiber (P : Finset Plane) (x y : Plane) : Finset Plane :=
  (P.erase x).filter (fun z => dist z x = dist y x)

def k (P : Finset Plane) (x y : Plane) : ℕ :=
  (distanceFiber P x y).card

def richPairs (P : Finset Plane) (s : ℝ) : Finset (Plane × Plane) :=
  (P ×ˢ P).filter (fun xy => xy.1 ≠ xy.2 ∧
    (P.card : ℝ) ^ s ≤ (k P xy.1 xy.2 : ℝ))

def pairFraction (P : Finset Plane) (s : ℝ) : ℝ :=
  (richPairs P s).card / ((P.card : ℝ) * ((P.card : ℝ) - 1))

def F (n : ℕ) (s : ℝ) : ℝ :=
  if 2 ≤ n then sSup {a : ℝ | ∃ P : Finset Plane, P.card = n ∧ a = pairFraction P s}
  else 0

theorem main (s : ℝ) (hs : 0<s) : Tendsto (fun n : ℕ => F n s) atTop (𝓝 0) := by
  sorry

end WeakPinned

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PinnedDistances.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.WeakPinned.main` must keep exactly the statement shown above: same names,
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
