# openai/math challenge `BufferedIsing` (family 218)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 218 of the release, *Conformal universality for weakly interacting and disordered Ising models*
(Probability and statistical mechanics). The family as a whole: Weak finite-range square-symmetric even multispin perturbations of the square-lattice Ising model preserve critical bulk spin and energy limits; weak square-symmetric contour interactions also yield chordal $\mathrm{SLE}_3$ interface limits. With sufficiently weak iid bond disorder of any fixed bounded nondegenerate mean-zero law, critical spin interfaces converge to the same law in probability over environments.

The challenge is `BufferedIsing`, also at `/opt/openai-math/challenges/BufferedIsing.lean`:

```lean
import Mathlib

namespace OAI

open scoped BigOperators Classical

namespace BufferedIsing

/-- A finite graph given by its edge list. Zero couplings can encode missing edges.
Edges are indexed separately so parallel edges are counted separately. -/
structure FiniteGraph (n m : ℕ) where
  left : Fin m → Fin n
  right : Fin m → Fin n
  coupling : Fin m → ℝ
  coupling_nonneg : ∀ e, 0 ≤ coupling e
  no_loops : ∀ e, left e ≠ right e

abbrev Spins (n : ℕ) := Fin n → Bool

def spin (b : Bool) : ℝ := if b then 1 else -1

noncomputable def energy {n m : ℕ} (G : FiniteGraph n m)
    (h : Fin n → ℝ) (σ : Spins n) : ℝ :=
  (∑ e, G.coupling e * spin (σ (G.left e)) * spin (σ (G.right e))) +
    ∑ v, h v * spin (σ v)

noncomputable def weight {n m : ℕ} (G : FiniteGraph n m)
    (h : Fin n → ℝ) (σ : Spins n) : ℝ := Real.exp (energy G h σ)

def AgreesOn {n : ℕ} (S : Finset (Fin n)) (σ τ : Spins n) : Prop :=
  ∀ v ∈ S, σ v = τ v

noncomputable def constrainedSum {n m : ℕ} (G : FiniteGraph n m)
    (h : Fin n → ℝ) (P : Spins n → Prop) : ℝ := by
  classical
  exact ∑ σ, if P σ then weight G h σ else 0

/-- Conditional probability of σ_I=a, with σ_J=b and σ_F=τ prescribed.
All sums are finite and all fields are finite real numbers. -/
noncomputable def conditionalProb {n m : ℕ} (G : FiniteGraph n m)
    (h : Fin n → ℝ) (I J F : Finset (Fin n)) (a b τ : Spins n) : ℝ :=
  constrainedSum G h (fun σ => AgreesOn I σ a ∧ AgreesOn J σ b ∧ AgreesOn F σ τ) /
    constrainedSum G h (fun σ => AgreesOn J σ b ∧ AgreesOn F σ τ)

/-- Edges remaining after DELETION, not pinning, of F. -/
def keptEdges {n m : ℕ} (G : FiniteGraph n m) (F : Finset (Fin n)) : Finset (Fin m) :=
  Finset.univ.filter (fun e => G.left e ∉ F ∧ G.right e ∉ F)

abbrev KeptVertex {n : ℕ} (F : Finset (Fin n)) := {v : Fin n // v ∉ F}

/-- Open-edge adjacency together with the two separate terminal identifications.
No virtual identification of common pins is present: those vertices are absent. -/
def comparisonRel {n m : ℕ} (G : FiniteGraph n m)
    (I J F : Finset (Fin n)) (ω : Finset (Fin m)) (u v : KeptVertex F) : Prop :=
  (u.val ∈ I ∧ v.val ∈ I) ∨ (u.val ∈ J ∧ v.val ∈ J) ∨
    ∃ e ∈ ω, (G.left e = u.val ∧ G.right e = v.val) ∨
      (G.left e = v.val ∧ G.right e = u.val)

/-- The equivalence closure implements components of the contracted open graph. -/
def comparisonSetoid {n m : ℕ} (G : FiniteGraph n m)
    (I J F : Finset (Fin n)) (ω : Finset (Fin m)) : Setoid (KeptVertex F) :=
  Relation.EqvGen.setoid (comparisonRel G I J F ω)

noncomputable def clusterCount {n m : ℕ} (G : FiniteGraph n m)
    (I J F : Finset (Fin n)) (ω : Finset (Fin m)) : ℕ :=
  Nat.card (Quotient (comparisonSetoid G I J F ω))

/-- Zero-field FK weight with q=2 and p_e=1-exp(-2 K_e).
Parallel edges may be retained: the measure after summing them is the measure
for the summed parallel coupling. Loops created by contraction do not change
components and cancel from connection probabilities. -/
noncomputable def fkWeight {n m : ℕ} (G : FiniteGraph n m)
    (I J F : Finset (Fin n)) (ω : Finset (Fin m)) : ℝ := by
  classical
  exact (2 : ℝ) ^ clusterCount G I J F ω *
    ∏ e ∈ keptEdges G F,
      if e ∈ ω then 1 - Real.exp (-2 * G.coupling e) else Real.exp (-2 * G.coupling e)

/-- Choose any i in I and j in J. The terminal connection is independent of
these choices because I and J are each identified. -/
noncomputable def qZero {n m : ℕ} (G : FiniteGraph n m)
    (I J F : Finset (Fin n)) (i j : KeptVertex F) : ℝ := by
  classical
  exact (∑ ω ∈ (keptEdges G F).powerset,
    if (comparisonSetoid G I J F ω).r i j then fkWeight G I J F ω else 0) /
    ∑ ω ∈ (keptEdges G F).powerset, fkWeight G I J F ω

/-- Any probability mixture of source prescriptions. Full configurations
index the mixture, but only their restrictions to J are used. Thus this is
exactly the class of all mixtures on {-1,+1}^J. -/
noncomputable def mixtureProb {n m : ℕ} (G : FiniteGraph n m)
    (h : Fin n → ℝ) (I J F : Finset (Fin n)) (a τ : Spins n)
    (mix : Spins n → ℝ) : ℝ :=
  ∑ b, mix b * conditionalProb G h I J F a b τ

/-- Finite-graph comparison for arbitrary probability mixtures on both sides.
Dirac mixtures recover the conditional laws. -/
theorem finite_graph_comparison {n m : ℕ} (G : FiniteGraph n m)
    (h : Fin n → ℝ) (I J F : Finset (Fin n))
    (hIJ : Disjoint I J) (hIF : Disjoint I F) (hJF : Disjoint J F)
    (i j : KeptVertex F) (hi : i.val ∈ I) (hj : j.val ∈ J)
    (a τ : Spins n) (mix mix' : Spins n → ℝ)
    (hmix : ∀ b, 0 ≤ mix b) (hmix' : ∀ b, 0 ≤ mix' b)
    (hmixsum : ∑ b, mix b = 1) (hmix'sum : ∑ b, mix' b = 1) :
    Real.exp (-4 * Real.artanh (qZero G I J F i j)) ≤
        mixtureProb G h I J F a τ mix / mixtureProb G h I J F a τ mix' ∧
      mixtureProb G h I J F a τ mix / mixtureProb G h I J F a τ mix' ≤
        Real.exp (4 * Real.artanh (qZero G I J F i j)) := by
  sorry

end BufferedIsing

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BufferedIsing.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.BufferedIsing.finite_graph_comparison` must keep exactly the statement shown above: same names,
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
