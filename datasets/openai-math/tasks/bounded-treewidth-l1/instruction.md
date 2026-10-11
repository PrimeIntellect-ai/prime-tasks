# openai/math challenge `BoundedTreewidthL1` (family 089)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 089 of the release, *Bounded-distortion $L_1$ embeddings of planar and bounded-treewidth graphs*
(Convex and metric geometry). The family as a whole: Resolves the planar and bounded-treewidth cases of the Gupta–Newman–Rabinovich–Sinclair conjecture. Shortest-path metrics of finite connected graphs with arbitrary positive edge lengths embed into real $L_1$ with universal distortion for planar graphs, and distortion depending only on treewidth for bounded-treewidth graphs. The corresponding multicommodity flow–cut gaps are uniformly bounded.

The challenge is `BoundedTreewidthL1`, also at `/opt/openai-math/challenges/BoundedTreewidthL1.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace BoundedTreewidthL1

universe u_1

variable {V : Type u_1} (G : SimpleGraph V)

/-- Sum of the given positive real edge lengths along a graph walk. -/
def walkLength (ℓ : G.edgeSet → ℝ) : {u v : V} → G.Walk u v → ℝ
  | _, _, .nil => 0
  | u, _, .cons (v := v) h p => ℓ ⟨s(u, v), h⟩ + walkLength ℓ p

noncomputable def shortestPathDistance (ℓ : G.edgeSet → ℝ) (u v : V) : ℝ :=
  sInf {r : ℝ | ∃ p : G.Walk u v, p.IsPath ∧ walkLength G ℓ p = r}

def HasTreeDecomposition [DecidableEq V] (k : ℕ) : Prop :=
  ∃ n : ℕ, ∃ T : SimpleGraph (Fin n), ∃ bag : Fin n → Finset V,
    T.IsTree ∧
    (∀ v : V, ∃ t, v ∈ bag t) ∧
    (∀ u v : V, G.Adj u v → ∃ t, u ∈ bag t ∧ v ∈ bag t) ∧
    (∀ v : V, (T.induce {t | v ∈ bag t}).Connected) ∧
    (∀ t, (bag t).card ≤ k)

/-- A map to genuine finite-dimensional real ℓ₁, not just a cut pseudometric. -/
def HasL1Embedding (ℓ : G.edgeSet → ℝ) (C : ℝ) : Prop :=
  ∃ m : ℕ, ∃ F : V → PiLp (1 : ENNReal) (fun _ : Fin m => ℝ),
    ∀ u v : V,
      shortestPathDistance G ℓ u v ≤ ‖F u - F v‖ ∧
      ‖F u - F v‖ ≤ C * shortestPathDistance G ℓ u v

def MainStatement : Prop :=
  ∀ k : ℕ, 2 ≤ k → ∃ C : ℝ, 1 ≤ C ∧
    ∀ (V : Type) [Fintype V] [DecidableEq V] [Nonempty V]
      (G : SimpleGraph V),
      G.Connected → HasTreeDecomposition G k →
      ∀ ℓ : G.edgeSet → ℝ, (∀ e, 0 < ℓ e) → HasL1Embedding G ℓ C

theorem main_theorem : MainStatement := by
  sorry

end BoundedTreewidthL1

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BoundedTreewidthL1.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.BoundedTreewidthL1.main_theorem` must keep exactly the statement shown above: same names,
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
