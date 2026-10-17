# openai/math challenge `CriticalZ3` (family 213)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 213 of the release, *No infinite critical clusters on quasi-transitive graphs*
(Probability and statistical mechanics). The family as a whole: Resolves the Benjamini–Schramm criticality conjecture for bond percolation on every infinite connected locally finite quasi-transitive graph with $p_c<1$: at the critical probability, there is almost surely no infinite cluster. The family also establishes this conclusion for both nearest-neighbor bond and site percolation on $\mathbb Z^3$.

The challenge is `CriticalZ3`, also at `/opt/openai-math/challenges/CriticalZ3.lean`:

```lean
import Mathlib

namespace OAI

open MeasureTheory ProbabilityTheory

namespace CriticalZ3

abbrev Vertex := Fin 3 → ℤ
abbrev Bond := Vertex × Fin 3
abbrev BondConfig := Bond → Bool
abbrev SiteConfig := Vertex → Bool

def step (x : Vertex) (i : Fin 3) : Vertex := fun j => x j + if i = j then 1 else 0

def NearestNeighbor (x y : Vertex) : Prop :=
  ∃ i : Fin 3, y = step x i ∨ x = step y i

def BondOpen (ω : BondConfig) (x y : Vertex) : Prop :=
  (∃ i : Fin 3, y = step x i ∧ ω (x, i) = true) ∨
  (∃ i : Fin 3, x = step y i ∧ ω (y, i) = true)

def SiteOpen (ω : SiteConfig) (x y : Vertex) : Prop :=
  NearestNeighbor x y ∧ ω x = true ∧ ω y = true

def BondConnected (ω : BondConfig) (x y : Vertex) : Prop :=
  Relation.ReflTransGen (BondOpen ω) x y

def SiteConnected (ω : SiteConfig) (x y : Vertex) : Prop :=
  ω x = true ∧ Relation.ReflTransGen (SiteOpen ω) x y

def bondCluster (ω : BondConfig) (x : Vertex) : Set Vertex :=
  {y | BondConnected ω x y}

def siteCluster (ω : SiteConfig) (x : Vertex) : Set Vertex :=
  {y | SiteConnected ω x y}

def bondInfiniteAt (x : Vertex) : Set BondConfig := {ω | (bondCluster ω x).Infinite}
def siteInfiniteAt (x : Vertex) : Set SiteConfig := {ω | (siteCluster ω x).Infinite}

noncomputable def parameter (p : ℝ) : Set.Icc (0 : ℝ) 1 :=
  ⟨max 0 (min 1 p), le_max_left _ _, max_le (by norm_num) (min_le_left _ _)⟩

noncomputable def bondLaw (p : ℝ) : Measure BondConfig :=
  Measure.infinitePi (fun _ : Bond => bernoulliMeasure true false (parameter p))

noncomputable def siteLaw (p : ℝ) : Measure SiteConfig :=
  Measure.infinitePi (fun _ : Vertex => bernoulliMeasure true false (parameter p))

noncomputable def bondCritical : ℝ :=
  sInf {p : ℝ | p ∈ Set.Icc (0 : ℝ) 1 ∧ 0 < bondLaw p (bondInfiniteAt 0)}

noncomputable def siteCritical : ℝ :=
  sInf {p : ℝ | p ∈ Set.Icc (0 : ℝ) 1 ∧ 0 < siteLaw p (siteInfiniteAt 0)}

theorem critical_no_infinite :
    (∀ᵐ ω ∂bondLaw bondCritical, ∀ x : Vertex, (bondCluster ω x).Finite) ∧
    (∀ᵐ ω ∂siteLaw siteCritical, ∀ x : Vertex, (siteCluster ω x).Finite) := by
  sorry

end CriticalZ3

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CriticalZ3.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CriticalZ3.critical_no_infinite` must keep exactly the statement shown above: same names,
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
