# openai/math challenge `FreeIsing` (family 236)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 236 of the release, *The factor-of-IID threshold for free Ising states on trees*
(Probability and statistical mechanics). The family as a whole: Determines when the free zero-field ferromagnetic Ising state on the infinite $d$-regular tree is a factor of independent vertex labels: exactly when $\tanh\beta\le(d-1)^{-1/2}$, including equality, for $d\ge3$ and $\beta\ge0$. The construction uses no root and is almost surely equivariant for each fixed tree automorphism, resolving the ferromagnetic case of Lyons's question.

The challenge is `FreeIsing`, also at `/opt/openai-math/challenges/FreeIsing.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open MeasureTheory

namespace Problem367

abbrev TreeVertex (d : ℕ) :=
  {word : List (Fin d) // List.IsChain (fun first second : Fin d => first ≠ second) word}

def treeAdj {d : ℕ} (u v : TreeVertex d) : Prop :=
  (∃ c : Fin d, v.1 = u.1 ++ [c]) ∨
  (∃ c : Fin d, u.1 = v.1 ++ [c])

structure TreeAut (d : ℕ) where
  toEquiv : TreeVertex d ≃ TreeVertex d
  map_adj : ∀ u v, treeAdj (toEquiv u) (toEquiv v) ↔ treeAdj u v

def relabel {d : ℕ} {α : Type*} (g : TreeAut d)
    (x : TreeVertex d → α) : TreeVertex d → α :=
  fun v => x (g.toEquiv.symm v)

inductive IsingSpin where
  | neg
  | pos
  deriving DecidableEq

protected abbrev IsingSpin.enumList : List IsingSpin := [.neg, .pos]

protected theorem IsingSpin.enumList_getElem?_ctorIdx_eq (x : IsingSpin) :
    IsingSpin.enumList[x.ctorIdx]? = some x := by
  cases x <;> rfl

protected theorem IsingSpin.enumList_nodup : IsingSpin.enumList.Nodup := by decide

instance : Fintype IsingSpin where
  elems := ⟨IsingSpin.enumList, IsingSpin.enumList_nodup⟩
  complete x := by cases x <;> decide

instance isingSpinMeasurable : MeasurableSpace IsingSpin := ⊤

def uniform01 : Measure ℝ :=
  volume.restrict (Set.Icc (0 : ℝ) 1)

instance uniform01Probability : IsProbabilityMeasure uniform01 where
  measure_univ := by simp [uniform01]

def labelMeasure (d : ℕ) : Measure (TreeVertex d → ℝ) := by
  classical
  exact Measure.infinitePi (fun _ : TreeVertex d => uniform01)

def ConnectedFinset {d : ℕ} (D : Finset (TreeVertex d)) : Prop :=
  D.Nonempty ∧
    ∀ u ∈ D, ∀ v ∈ D,
      Relation.ReflTransGen
        (fun x y : TreeVertex d => x ∈ D ∧ y ∈ D ∧ treeAdj x y) u v

def inducedEdges {d : ℕ} (D : Finset (TreeVertex d)) :
    Finset (TreeVertex d × TreeVertex d) := by
  classical
  exact (D.product D).filter (fun e =>
    treeAdj e.1 e.2 ∧ e.1.1.length < e.2.1.length)

def freeCylinderWeight {d : ℕ} (theta : ℝ)
    (D : Finset (TreeVertex d)) (eta : TreeVertex d → IsingSpin) : ENNReal :=
  ENNReal.ofReal
    ((1 / 2 : ℝ) *
      Finset.prod (inducedEdges D) (fun e =>
        (1 + (if eta e.1 = eta e.2 then theta else -theta)) / 2))

def HasFreeIsingLaw {d : ℕ} (theta : ℝ)
    (mu : Measure (TreeVertex d → IsingSpin)) : Prop :=
  ∀ (D : Finset (TreeVertex d)), ConnectedFinset D →
    ∀ eta : TreeVertex d → IsingSpin,
      mu {x | ∀ v ∈ D, x v = eta v} = freeCylinderWeight theta D eta

def IsFactorOfIID (d : ℕ) (theta : ℝ) : Prop :=
  ∃ Phi : (TreeVertex d → ℝ) → (TreeVertex d → IsingSpin),
    Measurable Phi ∧
    HasFreeIsingLaw theta (Measure.map Phi (labelMeasure d)) ∧
    ∀ g : TreeAut d,
      ∀ᵐ U ∂labelMeasure d, Phi (relabel g U) = relabel g (Phi U)

theorem free_ising_factor_iff_threshold :
    ∀ (d : ℕ) (beta : ℝ), 3 ≤ d → 0 ≤ beta → (IsFactorOfIID d (Real.tanh beta) ↔ Real.tanh beta ≤ 1 / Real.sqrt ((d : ℝ) - 1)) := by
  sorry

end Problem367

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/FreeIsing.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Problem367.free_ising_factor_iff_threshold` must keep exactly the statement shown above: same names,
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
