# openai/math challenge `PlanarL1` (family 089)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 089 of the release, *Bounded-distortion $L_1$ embeddings of planar and bounded-treewidth graphs*
(Convex and metric geometry). The family as a whole: Resolves the planar and bounded-treewidth cases of the Gupta–Newman–Rabinovich–Sinclair conjecture. Shortest-path metrics of finite connected graphs with arbitrary positive edge lengths embed into real $L_1$ with universal distortion for planar graphs, and distortion depending only on treewidth for bounded-treewidth graphs. The corresponding multicommodity flow–cut gaps are uniformly bounded.

The challenge is `PlanarL1`, also at `/opt/openai-math/challenges/PlanarL1.lean`:

```lean
import Mathlib

namespace OAI

namespace PlanarL1

/-- A topological drawing by simple plane arcs, with injective vertex placement,
no vertex in an edge interior, and disjoint interiors for distinct unoriented edges. -/
def IsPlanar {V : Type} (G : SimpleGraph V) : Prop :=
  ∃ (point : V → ℝ × ℝ) (arc : ∀ u v : V, G.Adj u v → C(unitInterval, ℝ × ℝ)),
    Function.Injective point ∧
    (∀ u v h, (arc u v h) 0 = point u ∧ (arc u v h) 1 = point v) ∧
    (∀ u v h, Function.Injective (arc u v h)) ∧
    (∀ u v h (t : unitInterval) w, 0 < (t : ℝ) → (t : ℝ) < 1 →
      (arc u v h) t ≠ point w) ∧
    (∀ u v h x y k (s t : unitInterval),
      0 < (s : ℝ) → (s : ℝ) < 1 → 0 < (t : ℝ) → (t : ℝ) < 1 →
      (arc u v h) s = (arc x y k) t →
      (u = x ∧ v = y) ∨ (u = y ∧ v = x))

/-- The sum of edge lengths along a finite graph walk. -/
def walkLength {V : Type} {G : SimpleGraph V} (length : V → V → ℝ)
    {u v : V} : G.Walk u v → ℝ
  | .nil => 0
  | @SimpleGraph.Walk.cons _ _ u w _ _ p => length u w + walkLength length p

/-- The infimum of lengths of actual walks between the two vertices. -/
noncomputable def graphDistance {V : Type} (G : SimpleGraph V)
    (length : V → V → ℝ) (u v : V) : ℝ :=
  sInf (Set.range (fun p : G.Walk u v => walkLength length p))

/-- One universal distortion bound for finite connected planar graphs with
arbitrary symmetric positive edge lengths, realized in a real `L¹` space. -/
def MainStatement : Prop :=
  ∃ C : ℝ, 1 ≤ C ∧
    ∀ (n : ℕ) (G : SimpleGraph (Fin n)) (length : Fin n → Fin n → ℝ),
      G.Connected → IsPlanar G →
      (∀ u v, length u v = length v u) →
      (∀ u v, G.Adj u v → 0 < length u v) →
      ∃ (Ω : Type) (measurable : MeasurableSpace Ω)
          (μ : @MeasureTheory.Measure Ω measurable)
          (f : Fin n → @MeasureTheory.Lp Ω ℝ measurable _ 1 μ),
        ∀ x y, graphDistance G length x y ≤ ‖f x - f y‖ ∧
          ‖f x - f y‖ ≤ C * graphDistance G length x y

theorem planar_graph_metrics_embed_L1 : MainStatement := by
  sorry

end PlanarL1

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PlanarL1.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PlanarL1.planar_graph_metrics_embed_L1` must keep exactly the statement shown above: same names,
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
