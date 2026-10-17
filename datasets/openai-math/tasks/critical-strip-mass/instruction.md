# openai/math challenge `CriticalStripMass` (family 237)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 237 of the release, *The three-quarter diameter exponent for honeycomb walks*
(Probability and statistical mechanics). The family as a whole: Proves the diameter form of Nienhuis's predicted three-quarter exponent: a uniformly chosen $n$-step self-avoiding walk on the honeycomb lattice has diameter $n^{3/4+o(1)}$. Its local mass and covering numbers have exponent $4/3$. These estimates hold at every sufficiently large fixed length, simultaneously across scales, with arbitrarily high polynomial probability.

The challenge is `CriticalStripMass`, also at `/opt/openai-math/challenges/CriticalStripMass.lean`:

```lean
import Mathlib

namespace OAI

 

namespace CriticalStrip

noncomputable section
open scoped BigOperators
open Set MeasureTheory

def rho : ℝ := 1 / Real.sqrt (2 + Real.sqrt 2)
def c : ℝ := Real.cos (3 * Real.pi / 8)
def lambda : ℝ := Real.pi / 8
def d : ℝ := Real.cos (2 * lambda)
def C : ℝ := Real.cos lambda
def eta : ℝ := 2 * d - 1

abbrev Triangle := ℤ × ℕ × Bool

def up (i : ℤ) (j : ℕ) : Triangle := (i, j, true)
def down (i : ℤ) (j : ℕ) : Triangle := (i, j, false)

def upDownAdjacent (v w : Triangle) : Prop :=
  v.2.2 = true ∧ w.2.2 = false ∧
    ((v.2.1 = w.2.1 ∧ (w.1 = v.1 ∨ w.1 + 1 = v.1)) ∨
      (v.2.1 = w.2.1 + 1 ∧ v.1 = w.1))

def adjacent (v w : Triangle) : Prop := upDownAdjacent v w ∨ upDownAdjacent w v

 
def IsPath (N : ℕ) (finish : Triangle) (p : List Triangle) : Prop :=
  p.head? = some (up 0 0) ∧ p.getLast? = some finish ∧ p.Nodup ∧
  p.IsChain adjacent ∧ ∀ v ∈ p, v.2.1 < N

 
def archWeight (N : ℕ) (k : ℤ) (p : List Triangle) : ℝ := by
  classical
  exact if k ≠ 0 ∧ IsPath N (up k 0) p then rho ^ p.length else 0

 
def bridgeWeight (N : ℕ) (k : ℤ) (p : List Triangle) : ℝ := by
  classical
  exact if 0 < N ∧ IsPath N (down k (N - 1)) p then rho ^ p.length else 0

def K (N : ℕ) (k : ℤ) : ℝ := ∑' p, archWeight N k p
def bridgeKernel (N : ℕ) (k : ℤ) : ℝ := ∑' p, bridgeWeight N k p
def archMass (N : ℕ) : ℝ := ∑' k : ℤ, K N k
def bridgeMass (N : ℕ) : ℝ := ∑' k : ℤ, bridgeKernel N k
def moment (N : ℕ) : ℝ := ∑' k : ℕ, (k + 1 : ℝ) * K N (k + 1)

 
def StripSumsFinite (N : ℕ) : Prop :=
  (∀ k : ℤ, Summable (archWeight N k)) ∧
  (∀ k : ℤ, Summable (bridgeWeight N k)) ∧
  Summable (K N) ∧ Summable (bridgeKernel N) ∧
  Summable (fun k : ℕ => (k + 1 : ℝ) * K N (k + 1))

 
def Comparable (f g : ℕ → ℝ) : Prop :=
  ∃ lo hi : ℝ, 0 < lo ∧ 0 < hi ∧
    ∀ N : ℕ, 1 ≤ N → lo * g N ≤ f N ∧ f N ≤ hi * g N

 
def CriticalStripMass : Prop :=
  (∀ N : ℕ, 1 ≤ N → StripSumsFinite N) ∧
  (∀ N : ℕ, 1 ≤ N → c * archMass N + bridgeMass N = 1) ∧
  Comparable (fun N => moment (N + 1) - moment N) bridgeMass ∧
  Comparable moment (fun N => (N : ℝ) ^ (3 / 4 : ℝ)) ∧
  Comparable bridgeMass (fun N => (N : ℝ) ^ (-(1 / 4) : ℝ)) ∧
  (∀ N : ℕ, 1 ≤ N → bridgeMass (N + 1) ≤ bridgeMass N)

 

theorem critical_strip_mass : CriticalStripMass := by
  sorry

end
end CriticalStrip

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CriticalStripMass.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CriticalStrip.critical_strip_mass` must keep exactly the statement shown above: same names,
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
