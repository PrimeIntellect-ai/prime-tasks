# openai/math challenge `TriangleFace` (family 113)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 113 of the release, *Approximate counting and the perfect-matching entropy conjecture*
(Theoretical computer science). The family as a whole: Gives a fully polynomial randomized approximation scheme for counting perfect matchings in arbitrary finite simple graphs, with exact detection of zero counts. Also proves the perfect-matching entropy conjecture of Anari, Oveis Gharan, and Vinzant, bounding the maximum entropy of a matching law at every feasible edge-marginal vector in a loopless labelled multigraph, including boundary points.

The challenge is `TriangleFace`, also at `/opt/openai-math/challenges/TriangleFace.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped BigOperators Topology
open Filter

universe uV uE uIndex uι

namespace MatchingEntropyBounds

structure LooplessGraph (V : Type uV) (E : Type uE) where
  left : E → V
  right : E → V
  loopless : ∀ e, left e ≠ right e

variable {V : Type uV} {E : Type uE}
  [Fintype V] [Fintype E] [DecidableEq V] [DecidableEq E]

namespace LooplessGraph

def Incident (G : LooplessGraph V E) (v : V) (e : E) : Prop :=
  G.left e = v ∨ G.right e = v

instance incidentDecidable (G : LooplessGraph V E) (v : V) (e : E) :
    Decidable (G.Incident v e) := inferInstanceAs (Decidable (G.left e = v ∨ G.right e = v))

def IsPerfectMatching (G : LooplessGraph V E) (M : Finset E) : Prop :=
  ∀ v, ∃! e, e ∈ M ∧ G.Incident v e

abbrev Matching (G : LooplessGraph V E) := {M : Finset E // G.IsPerfectMatching M}

instance matchingFintype (G : LooplessGraph V E) : Fintype G.Matching :=
  Fintype.ofFinite _

def indicator (G : LooplessGraph V E) (M : G.Matching) (e : E) : ℝ :=
  if e ∈ M.val then 1 else 0

def polytope (G : LooplessGraph V E) : Set (E → ℝ) :=
  convexHull ℝ (Set.range G.indicator)

end LooplessGraph
end MatchingEntropyBounds
end

noncomputable section

open scoped BigOperators Topology
open Filter

universe uV uE uI uJ uA uB uC uW uF uD uι

namespace MatchingEntropyBounds.LooplessGraph

variable {V : Type uV} {E : Type uE} [Fintype V] [Fintype E] [DecidableEq V] [DecidableEq E]

def Crosses (G : LooplessGraph V E) (S : Finset V) (e : E) : Prop :=
  (G.left e ∈ S ∧ G.right e ∉ S) ∨ (G.left e ∉ S ∧ G.right e ∈ S)

instance crossesDecidable (G : LooplessGraph V E) (S : Finset V) (e : E) :
    Decidable (G.Crosses S e) := inferInstanceAs (Decidable
      ((G.left e ∈ S ∧ G.right e ∉ S) ∨ (G.left e ∉ S ∧ G.right e ∈ S)))

def cut (G : LooplessGraph V E) (S : Finset V) : Finset E :=
  Finset.univ.filter (G.Crosses S)

def degree (G : LooplessGraph V E) (x : E → ℝ) (v : V) : ℝ :=
  ∑ e, if G.Incident v e then x e else 0

def cutMass (G : LooplessGraph V E) (x : E → ℝ) (S : Finset V) : ℝ :=
  ∑ e ∈ G.cut S, x e

end MatchingEntropyBounds.LooplessGraph
end

noncomputable section

open scoped BigOperators Topology
open Filter

universe uV uE uI uJ uA uB uC uW uF uD uι

namespace MatchingEntropyBounds.Refined

section TriangleExpansion
variable {V : Type uV} {E : Type uE} [Fintype V] [Fintype E] [DecidableEq V] [DecidableEq E]

def triangleTip (v : V) (i : Fin 3) : V ⊕ Fin 2 := ![Sum.inl v, Sum.inr 0, Sum.inr 1] i

def triangleCollapse (v : V) : V ⊕ Fin 2 → V := Sum.elim id (fun _ => v)

def reattach (v : V) (i : Fin 3) (w : V) : V ⊕ Fin 2 :=
  if w = v then triangleTip v i else Sum.inl w

omit [Fintype V] [Fintype E] [DecidableEq E] in
theorem collapse_reattach (v : V) (i : Fin 3) (w : V) :
    triangleCollapse v (reattach v i w) = w := by
  by_cases h : w = v
  · subst w
    fin_cases i <;> simp [reattach,triangleTip,triangleCollapse]
  · simp [reattach,h,triangleCollapse]

def triangleExpansion (G : LooplessGraph V E) (c : E → Fin 3) (v : V) :
    LooplessGraph (V ⊕ Fin 2) (E ⊕ Fin 3) where
  left := Sum.elim (fun e => reattach v (c e) (G.left e)) (fun i => triangleTip v (i + 1))
  right := Sum.elim (fun e => reattach v (c e) (G.right e)) (fun i => triangleTip v (i + 2))
  loopless := by
    intro e h
    rcases e with e | i
    · have hh := congrArg (triangleCollapse v) h
      exact G.loopless e ((collapse_reattach v (c e) (G.left e)).symm.trans
        (hh.trans (collapse_reattach v (c e) (G.right e))))
    · fin_cases i <;> simp [triangleTip] at h

def triangleVertices (v : V) : Finset (V ⊕ Fin 2) := Finset.univ.image (triangleTip v)

end TriangleExpansion
end MatchingEntropyBounds.Refined
end

namespace CanonicalFace198

variable {A B : Type*} [AddCommGroup A] [Module ℝ A]
  [AddCommGroup B] [Module ℝ B]

def facesThrough (P : Set A) (x : A) : Set (Set A) :=
  {F | Convex ℝ F ∧ IsExtreme ℝ P F ∧ x ∈ F}

def minFace (P : Set A) (x : A) : Set A := ⋂₀ facesThrough P x

end CanonicalFace198

noncomputable section
open scoped BigOperators
open MatchingEntropyBounds MatchingEntropyBounds.Refined
namespace TriangleFace198
variable {V E : Type*} [Fintype V] [Fintype E] [DecidableEq V] [DecidableEq E]

def LocalLabels (G : LooplessGraph V E) (v : V) (c : E → Fin 3) : Prop :=
  ∀ i, ∃! e, G.Incident v e ∧ c e = i

def localEdge (G : LooplessGraph V E) (c : E → Fin 3) (v : V)
    (hc : LocalLabels G v c) (i : Fin 3) : E := Classical.choose (hc i)

def localExtension (G : LooplessGraph V E) (c : E → Fin 3) (v : V)
    (hc : LocalLabels G v c) : (E → ℝ) →ₗ[ℝ] (E ⊕ Fin 3 → ℝ) where
  toFun x := Sum.elim x (fun i => x (localEdge G c v hc i))
  map_add' x y := by ext e; cases e <;> rfl
  map_smul' a x := by ext e; cases e <;> rfl

def oldRestriction : (E ⊕ Fin 3 → ℝ) →ₗ[ℝ] (E → ℝ) where
  toFun y e := y (Sum.inl e)
  map_add' _ _ := rfl
  map_smul' _ _ := rfl

end TriangleFace198

end

noncomputable section
open scoped BigOperators
open MatchingEntropyBounds MatchingEntropyBounds.Refined
namespace TriangleFace198
universe uV uE
variable {V : Type uV} {E : Type uE} [instFintypeV : Fintype V] [Fintype E] [DecidableEq V] [instDecidableEqE : DecidableEq E]

theorem triangle_expansion_face {V : Type uV} {E : Type uE}
    [Fintype V] [Fintype E] [DecidableEq V] [DecidableEq E] (G : LooplessGraph V E) (v : V)
    (hdeg : Fintype.card {e : E // G.Incident v e} = 3)
    (_hmatching : Nonempty G.Matching) :
    ∃ (c : E → Fin 3) (hc : LocalLabels G v c),
      let H := triangleExpansion G c v
      let f := localExtension G c v hc
      let Q := {y | y ∈ H.polytope ∧ H.cutMass y (triangleVertices v) = 1}
      f '' G.polytope = Q ∧
      Convex ℝ Q ∧ IsExtreme ℝ H.polytope Q ∧
      (∀ x, oldRestriction (f x) = x) ∧
      (∀ y ∈ Q, f (oldRestriction y) = y) ∧
      (∀ x e, f x (Sum.inl e) = x e) ∧
      (∀ x i, f x (Sum.inr i) = x (localEdge G c v hc i)) ∧
      (∀ x, (∀ e, x e = (1/3 : ℝ)) → ∀ e, f x e = (1/3 : ℝ)) ∧
      (∀ x ∈ G.polytope, CanonicalFace198.minFace H.polytope (f x) = f '' CanonicalFace198.minFace G.polytope x)  := by
  sorry

end TriangleFace198
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TriangleFace.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.TriangleFace198.triangle_expansion_face` must keep exactly the statement shown above: same names,
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
