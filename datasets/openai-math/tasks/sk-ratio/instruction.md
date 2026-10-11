# openai/math challenge `SKRatio` (family 227)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 227 of the release, *The dynamical phase transition in the Sherrington–Kirkpatrick model*
(Probability and statistical mechanics). The family as a whole: For zero-field Gaussian SK heat-bath dynamics with rate-one updates per spin, proves worst-start cutoff on the $\log n$ scale for fixed $0\le\beta<1$, mixing time $n^{2/3+o(1)}$ at $\beta=1$, and stretched-exponential mixing from a Gibbs-sampled fixed starting configuration for $\beta>1$, in probability over disorder. At criticality, rescaled stationary and quench autocorrelation processes have universal random limits for Gaussian and Rademacher disorder; the quench limit relaxes to the stationary limit.

The challenge is `SKRatio`, also at `/opt/openai-math/challenges/SKRatio.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators Topology
open MeasureTheory ProbabilityTheory Filter

namespace SKRatio

abbrev Spin (n : ℕ) := Fin n → Bool
abbrev Edge (n : ℕ) := {p : Fin n × Fin n // p.1 < p.2}
abbrev Disorder (n : ℕ) := Edge n → ℝ

def spinValue (b : Bool) : ℝ := if b then 1 else -1

def coupling {n : ℕ} (g : Disorder n) (i j : Fin n) : ℝ :=
  if h : i < j then g ⟨(i, j), h⟩ else
    if h : j < i then g ⟨(j, i), h⟩ else 0

def hamiltonian {n : ℕ} (g : Disorder n) (h : Fin n → ℝ) (x : Spin n) : ℝ :=
  (1 / 2 : ℝ) * ∑ i, ∑ j, spinValue (x i) * coupling g i j * spinValue (x j) +
    ∑ i, h i * spinValue (x i)

def weight {n : ℕ} (g : Disorder n) (h : Fin n → ℝ) (x : Spin n) : ℝ :=
  Real.exp (hamiltonian g h x)

def partition {n : ℕ} (g : Disorder n) (h : Fin n → ℝ) : ℝ :=
  ∑ x, weight g h x

def mass {n : ℕ} (g : Disorder n) (h : Fin n → ℝ) (x : Spin n) : ℝ :=
  weight g h x / partition g h

def flip {n : ℕ} (i : Fin n) (x : Spin n) : Spin n :=
  Function.update x i (!(x i))

def disorderLaw (β : ℝ) (n : ℕ) : Measure (Disorder n) :=
  Measure.pi (fun _ : Edge n => gaussianReal 0 (Real.toNNReal (β ^ 2 / n)))

def siteKernel {n : ℕ} (g : Disorder n) (i : Fin n) :
    Matrix (Spin n) (Spin n) ℝ := fun x y =>
  (if y = x then mass g 0 x / (mass g 0 x + mass g 0 (flip i x)) else 0) +
  (if y = flip i x then
    mass g 0 (flip i x) / (mass g 0 x + mass g 0 (flip i x)) else 0)

def transition {n : ℕ} (g : Disorder n) : Matrix (Spin n) (Spin n) ℝ :=
  if n = 0 then 1 else fun x y => (∑ i, siteKernel g i x y) / (n : ℝ)

def totalVariation {α : Type*} [Fintype α] (p q : α → ℝ) : ℝ :=
  (1 / 2 : ℝ) * ∑ y, |p y - q y|

def discreteDistance {n : ℕ} (g : Disorder n) (k : ℕ) : ℝ :=
  Finset.univ.sup' Finset.univ_nonempty
    (fun x : Spin n => totalVariation ((transition g ^ k) x) (mass g 0))

def mixingTime {n : ℕ} (g : Disorder n) (ε : ℝ) : ℕ :=
  sInf {k : ℕ | discreteDistance g k ≤ ε}

theorem ratio_cutoff (β ε η : ℝ)
    (hβ0 : 0 ≤ β) (hβhalf : β < 1 / 2)
    (hε0 : 0 < ε) (hεhalf : ε < 1 / 2) (hη : 0 < η) :
    Tendsto
      (fun n : ℕ => disorderLaw β n
        {g : Disorder n | 1 + η <
          (mixingTime g ε : ℝ) / (mixingTime g (1 - ε) : ℝ)})
      atTop (𝓝 0) ∧
    (∀ᶠ n : ℕ in atTop, ∀ g : Disorder n, 0 < mixingTime g (1 - ε)) := by
  sorry

end SKRatio

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SKRatio.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SKRatio.ratio_cutoff` must keep exactly the statement shown above: same names,
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
