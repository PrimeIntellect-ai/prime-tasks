# openai/math challenge `HoneycombFreeEnergy` (family 237)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 237 of the release, *The three-quarter diameter exponent for honeycomb walks*
(Probability and statistical mechanics). The family as a whole: Proves the diameter form of Nienhuis's predicted three-quarter exponent: a uniformly chosen $n$-step self-avoiding walk on the honeycomb lattice has diameter $n^{3/4+o(1)}$. Its local mass and covering numbers have exponent $4/3$. These estimates hold at every sufficiently large fixed length, simultaneously across scales, with arbitrarily high polynomial probability.

The challenge is `HoneycombFreeEnergy`, also at `/opt/openai-math/challenges/HoneycombFreeEnergy.lean`:

```lean
import Mathlib

namespace OAI

/-! Existence of the fixed-length forced free energy of honeycomb walks. -/

noncomputable section
open scoped ENNReal Topology
open Filter

namespace HoneycombForce

structure Vertex where
  col : ℤ
  row : ℤ
  up : Bool
  deriving DecidableEq

def up (i j : ℤ) : Vertex := ⟨i, j, true⟩

def down (i j : ℤ) : Vertex := ⟨i, j, false⟩

def rowSpacing : ℝ := Real.sqrt 3 / 2

def position (v : Vertex) : ℂ :=
  if v.up then
    ⟨(v.col : ℝ) + (v.row : ℝ) / 2 + 1/2,
      rowSpacing * ((v.row : ℝ) + 1/3)⟩
  else
    ⟨(v.col : ℝ) + (v.row : ℝ) / 2 + 1,
      rowSpacing * ((v.row : ℝ) + 2/3)⟩

def rho : ℝ := (Real.sqrt (2 + Real.sqrt 2))⁻¹

def neighbors (v : Vertex) : Finset Vertex :=
  if v.up then
    {down v.col (v.row-1), down v.col v.row, down (v.col-1) v.row}
  else
    {up v.col (v.row+1), up v.col v.row, up (v.col+1) v.row}

def walkLists (o : Vertex) : ℕ → Finset (List Vertex)
  | 0 => {[o]}
  | n+1 => (neighbors o).biUnion (fun v => (walkLists v n).image (List.cons o))

def saws (o : Vertex) (n : ℕ) : Finset (List Vertex) :=
  (walkLists o n).filter List.Nodup

def endpoint (o : Vertex) (γ : List Vertex) : Vertex := γ.getLastD o

def displacement (o : Vertex) (γ : List Vertex) : ℂ :=
  position (endpoint o γ) - position o

def projection (e z : ℂ) : ℝ := (star e * z).re

def partition (o : Vertex) (e : ℂ) (s : ℝ) (n : ℕ) : ℝ :=
  ∑ γ ∈ saws o n, rho ^ n * Real.exp (s * projection e (displacement o γ))

def logPartition (o : Vertex) (e : ℂ) (s : ℝ) (n : ℕ) : ℝ :=
  Real.log (partition o e s n) / (n : ℝ)

def freeEnergy (o : Vertex) (e : ℂ) (s : ℝ) : ℝ :=
  Filter.limUnder atTop (logPartition o e s)

theorem logPartition_tendsto (o : Vertex) (e : ℂ) (s : ℝ) :
    Tendsto (logPartition o e s) atTop (𝓝 (freeEnergy o e s)) := by
  sorry

end HoneycombForce

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/HoneycombFreeEnergy.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.HoneycombForce.logPartition_tendsto` must keep exactly the statement shown above: same names,
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
