# openai/math challenge `SKBarriers` (family 227)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 227 of the release, *The dynamical phase transition in the Sherrington–Kirkpatrick model*
(Probability and statistical mechanics). The family as a whole: For zero-field Gaussian SK heat-bath dynamics with rate-one updates per spin, proves worst-start cutoff on the $\log n$ scale for fixed $0\le\beta<1$, mixing time $n^{2/3+o(1)}$ at $\beta=1$, and stretched-exponential mixing from a Gibbs-sampled fixed starting configuration for $\beta>1$, in probability over disorder. At criticality, rescaled stationary and quench autocorrelation processes have universal random limits for Gaussian and Rademacher disorder; the quench limit relaxes to the stationary limit.

The challenge is `SKBarriers`, also at `/opt/openai-math/challenges/SKBarriers.lean`:

```lean
import Mathlib

namespace OAI

section

section

noncomputable section
open scoped BigOperators Topology
open MeasureTheory ProbabilityTheory Filter

namespace SK
abbrev Config (n : ℕ) := Fin n → Bool
abbrev Edge (n : ℕ) := {p : Fin n × Fin n // p.1 < p.2}
abbrev Disorder (n : ℕ) := Edge n → ℝ

def spin (b : Bool) : ℝ := if b then 1 else -1

def hamiltonian {n : ℕ} (J : Disorder n) (x : Config n) : ℝ :=
  (∑ e : Edge n, J e * spin (x e.val.1) * spin (x e.val.2)) / Real.sqrt n

def partition {n : ℕ} (β : ℝ) (J : Disorder n) : ℝ :=
  ∑ x : Config n, Real.exp (β * hamiltonian J x)

def gibbs {n : ℕ} (β : ℝ) (J : Disorder n) (x : Config n) : ℝ :=
  Real.exp (β * hamiltonian J x) / partition β J

def coupling {n : ℕ} (J : Disorder n) (i j : Fin n) : ℝ :=
  if h : i < j then J ⟨(i, j), h⟩ else
    if h : j < i then J ⟨(j, i), h⟩ else 0

def localField {n : ℕ} (J : Disorder n) (x : Config n) (i : Fin n) : ℝ :=
  (∑ j : Fin n, coupling J i j * spin (x j)) / Real.sqrt n

def heatBath {n : ℕ} (β : ℝ) (J : Disorder n) (x y : Config n) : ℝ :=
  (∑ i : Fin n, if Function.update x i (y i) = y then
    Real.exp (β * spin (y i) * localField J x i) /
      (2 * Real.cosh (β * localField J x i)) else 0) / n

def discreteKernel {n : ℕ} (β : ℝ) (J : Disorder n) : ℕ → Config n → Config n → ℝ
  | 0, x, y => if x = y then 1 else 0
  | k + 1, x, y => ∑ z : Config n, heatBath β J x z * discreteKernel β J k z y

def continuousKernel {n : ℕ} (β : ℝ) (J : Disorder n) (t : ℝ)
    (x y : Config n) : ℝ :=
  ∑' k : ℕ, (Real.exp (-(n : ℝ) * t) * ((n : ℝ) * t) ^ k /
    (Nat.factorial k : ℝ)) * discreteKernel β J k x y

def discreteDistance {n : ℕ} (β : ℝ) (J : Disorder n)
    (x : Config n) (k : ℕ) : ℝ :=
  (1 / 2 : ℝ) * ∑ y : Config n, |discreteKernel β J k x y - gibbs β J y|

def continuousDistance {n : ℕ} (β : ℝ) (J : Disorder n)
    (x : Config n) (t : ℝ) : ℝ :=
  (1 / 2 : ℝ) * ∑ y : Config n, |continuousKernel β J t x y - gibbs β J y|

def disorderLaw (n : ℕ) : Measure (Disorder n) :=
  Measure.pi (fun _ : Edge n => gaussianReal 0 1)

def kappa : ℝ := 1 / 10000

def timeScale (n : ℕ) : ℝ := Real.exp ((n : ℝ) ^ kappa)

def continuousBadMass (β : ℝ) (n : ℕ) : ℝ :=
  ∫ J : Disorder n, (∑ x : Config n, if 1 / 4 < continuousDistance β J x (timeScale n)
    then gibbs β J x else 0) ∂disorderLaw n

def discreteBadMass (β : ℝ) (n : ℕ) : ℝ :=
  ∫ J : Disorder n, (∑ x : Config n, if 1 / 4 < discreteDistance β J x ⌊timeScale n⌋₊
    then gibbs β J x else 0) ∂disorderLaw n

end SK
end
end
end

noncomputable section
open scoped BigOperators Topology
open MeasureTheory ProbabilityTheory Filter

namespace SK

theorem main (β : ℝ) (hβ : 1 < β) :
    Tendsto (continuousBadMass β) atTop (𝓝 1) ∧
    Tendsto (discreteBadMass β) atTop (𝓝 1) := by
  sorry

end SK
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SKBarriers.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SK.main` must keep exactly the statement shown above: same names,
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
