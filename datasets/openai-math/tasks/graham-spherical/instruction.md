# openai/math challenge `GrahamSpherical` (family 172)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 172 of the release, *Classification of finite Euclidean Ramsey configurations*
(Combinatorics). The family as a whole: Classifies finite point configurations that occur monochromatically, at their original scale, in every finite coloring of sufficiently high-dimensional Euclidean space. The characterization is an algebraic condition over the coordinate field. It also disproves the Leader–Russell–Walters conjecture that every such configuration is a subset of a finite transitive set.

The challenge is `GrahamSpherical`, also at `/opt/openai-math/challenges/GrahamSpherical.lean`:

```lean
import Mathlib.Analysis.InnerProductSpace.PiL2
import Mathlib.Topology.Algebra.InfiniteSum.Real

namespace OAI

noncomputable section

namespace GrahamSpherical

abbrev Point (n : ℕ) := EuclideanSpace ℝ (Fin n)
abbrev Label := Fin 3 × Fin 4

def parameter : ℝ := ∑' m : ℕ, 1 / (10 : ℝ) ^ ((m + 1).factorial)

def u : ℝ := (1 - parameter ^ 2) / (1 + parameter ^ 2)
def v : ℝ := (2 * parameter) / (1 + parameter ^ 2)

def squareCoordinate (q : Fin 4) : Fin 2 → ℝ :=
  if q = 0 then ![1, 0] else
  if q = 1 then ![-1, 0] else
  if q = 2 then ![0, 1] else ![0, -1]

def coordinates (i : Label) : Fin 2 → ℝ :=
  let q := squareCoordinate i.2
  if i.1 = 0 then ![u * q 0 - v * q 1, v * q 0 + u * q 1] else
  if i.1 = 1 then ![u * q 0 + v * q 1, -v * q 0 + u * q 1] else q

def vertex (i : Label) : Point 2 := WithLp.toLp 2 (coordinates i)

def witness : Set (Point 2) := Set.range vertex

def AvoidsCopy {d n r : ℕ} (X : Set (Point d)) (color : Point n → Fin r) : Prop :=
  ¬ ∃ f : X → Point n, Isometry f ∧ ∃ c : Fin r, ∀ x, color (f x) = c

def EuclideanRamsey {d : ℕ} (X : Set (Point d)) : Prop :=
  ∀ r : ℕ, 0 < r → ∃ n : ℕ, 0 < n ∧
    ∀ color : Point n → Fin r,
      ∃ f : X → Point n, Isometry f ∧ ∃ c : Fin r, ∀ x, color (f x) = c

end GrahamSpherical

end

namespace GrahamSpherical.Specification

def FullAuthoredResult : Prop :=
  witness.ncard = 12 ∧
  witness ⊆ Metric.sphere (0 : Point 2) 1 ∧
  (∀ n : ℕ, 0 < n → ∃ color : Point n → Fin 50, AvoidsCopy witness color) ∧
  ¬ EuclideanRamsey witness

end GrahamSpherical.Specification

noncomputable section

namespace GrahamSpherical

theorem full_main : Specification.FullAuthoredResult := by
  sorry

end GrahamSpherical

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GrahamSpherical.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.GrahamSpherical.full_main` must keep exactly the statement shown above: same names,
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
