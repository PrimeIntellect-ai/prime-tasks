# openai/math challenge `CannonGeometricAction` (family 246)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 246 of the release, *Cannon's conjecture*
(Group theory). The family as a whole: Every word-hyperbolic group with boundary homeomorphic to $S^2$ admits a proper cocompact isometric action on hyperbolic three-space with finite kernel, proving Cannon's conjecture. Every torsion-free such group is therefore the fundamental group of a closed hyperbolic three-manifold.

The challenge is `CannonGeometricAction`, also at `/opt/openai-math/challenges/CannonGeometricAction.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
namespace CannonRelease

universe u

structure CayleyData (G : Type u) [Group G] where
  generators : Finset G
  symmetric : ∀ x ∈ generators, x⁻¹ ∈ generators
  connected : (SimpleGraph.mulCayley (generators : Set G)).Connected

def CayleyData.graph {G : Type u} [Group G] (D : CayleyData G) : SimpleGraph G :=
  SimpleGraph.mulCayley (D.generators : Set G)

/-- A uniform thinness constant for geodesic triangles in the Cayley graph. -/
def CayleyData.ThinTriangles {G : Type u} [Group G] (D : CayleyData G) : Prop :=
  ∃ δ : ℕ, ∀ x y z : G,
    ∀ p : D.graph.Walk x y, ∀ q : D.graph.Walk y z, ∀ r : D.graph.Walk z x,
      p.length = D.graph.dist x y → q.length = D.graph.dist y z →
      r.length = D.graph.dist z x →
      ∀ a ∈ p.support, ∃ b ∈ q.support ++ r.support, D.graph.dist a b ≤ δ

/-- Based geodesic rays, parametrized at integer times. -/
def BasedRay {G : Type u} [Group G] (D : CayleyData G) :=
  {r : ℕ → G // r 0 = 1 ∧ ∀ i j, D.graph.dist (r i) (r j) = Nat.dist i j}

instance {G : Type u} [Group G] [TopologicalSpace G] (D : CayleyData G) :
    TopologicalSpace (BasedRay D) := inferInstanceAs (TopologicalSpace {r : ℕ → G //
      r 0 = 1 ∧ ∀ i j, D.graph.dist (r i) (r j) = Nat.dist i j})

/-- Finite synchronous distance, equivalent to asymptoticity for based rays. -/
def raySetoid {G : Type u} [Group G] (D : CayleyData G) : Setoid (BasedRay D) where
  r r s := ∃ C : ℕ, ∀ n, D.graph.dist (r.val n) (s.val n) ≤ C
  iseqv := by
    constructor
    · intro r
      exact ⟨0, fun n => by simp⟩
    · rintro r s ⟨C, hC⟩
      exact ⟨C, fun n => by rw [SimpleGraph.dist_comm]; exact hC n⟩
    · rintro r s t ⟨C, hC⟩ ⟨E, hE⟩
      refine ⟨C + E, fun n => ?_⟩
      exact le_trans ((D.connected (r.val n) (s.val n)).dist_triangle_left (t.val n))
        (Nat.add_le_add (hC n) (hE n))

def Boundary {G : Type u} [Group G] (D : CayleyData G) := Quotient (raySetoid D)

instance {G : Type u} [Group G] [TopologicalSpace G] (D : CayleyData G) :
    TopologicalSpace (Boundary D) :=
  inferInstanceAs (TopologicalSpace (Quotient (raySetoid D)))

abbrev SphereTwo := {x : EuclideanSpace ℝ (Fin 3) // x ∈ Metric.sphere 0 1}

/-- The upper-half-space model of hyperbolic three-space. -/
def HyperbolicThree := {x : Fin 3 → ℝ // 0 < x 2}

instance : TopologicalSpace HyperbolicThree :=
  inferInstanceAs (TopologicalSpace {x : Fin 3 → ℝ // 0 < x 2})

def hyperbolicDist (x y : HyperbolicThree) : ℝ :=
  Real.arcosh (1 + (∑ i : Fin 3, (x.val i - y.val i) ^ 2) / (2 * x.val 2 * y.val 2))

/-- The full isometry group, including orientation-reversing isometries. -/
def hyperbolicIsometries : Subgroup (HyperbolicThree ≃ₜ HyperbolicThree) where
  carrier := {f | ∀ x y, hyperbolicDist (f x) (f y) = hyperbolicDist x y}
  one_mem' := by
    change ∀ x y, hyperbolicDist x y = hyperbolicDist x y
    intros
    rfl
  mul_mem' := by
    intro f g hf hg x y
    exact (hf (g x) (g y)).trans (hg x y)
  inv_mem' := by
    intro f hf x y
    simpa using (hf (f.symm x) (f.symm y)).symm

abbrev H3Isom := ↥hyperbolicIsometries

def ProperAction {G : Type u} [Group G] (ρ : G →* H3Isom) : Prop :=
  ∀ K : Set HyperbolicThree, IsCompact K →
    {g : G | ∃ x ∈ K, (ρ g).val x ∈ K}.Finite

def CocompactAction {G : Type u} [Group G] (ρ : G →* H3Isom) : Prop :=
  ∃ K : Set HyperbolicThree, IsCompact K ∧
    ∀ x : HyperbolicThree, ∃ g : G, ∃ y ∈ K, (ρ g).val y = x

theorem cannon (G : Type u) [Group G] [TopologicalSpace G] [DiscreteTopology G]
    (D : CayleyData G) (hthin : D.ThinTriangles)
    (hsphere : Nonempty (Boundary D ≃ₜ SphereTwo)) :
    ∃ ρ : G →* H3Isom, ProperAction ρ ∧ CocompactAction ρ ∧
      (ρ.ker : Set G).Finite := by
  sorry

end CannonRelease
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CannonGeometricAction.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.CannonRelease.cannon` must keep exactly the statement shown above: same names,
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
