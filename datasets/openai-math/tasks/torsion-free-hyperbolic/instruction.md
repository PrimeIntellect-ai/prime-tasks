# openai/math challenge `TorsionFreeHyperbolic` (family 252)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 252 of the release, *A non-residually-finite torsion-free hyperbolic group*
(Group theory). The family as a whole: Constructs a torsion-free word-hyperbolic group that is not residually finite, answering the residual-finiteness question negatively. One fixed nonidentity element is killed by every finite-dimensional linear representation over every commutative field, so the group is not linear over any such field.

The challenge is `TorsionFreeHyperbolic`, also at `/opt/openai-math/challenges/TorsionFreeHyperbolic.lean`:

```lean
import Mathlib

namespace OAI

namespace Release075

universe u v

/-- No nonidentity element has finite order. This does not assert unique roots. -/
def TorsionFree (G : Type u) [Group G] : Prop :=
  ∀ (g : G) (n : ℕ), 0 < n → g ^ n = 1 → g = 1

/-- A shortest edge path in the unit-edge graph. -/
def Geodesic {V : Type u} (X : SimpleGraph V) {x y : V} (p : X.Walk x y) : Prop :=
  p.length = X.dist x y

/-- Each vertex of `p` is within `δ` of a vertex of `q` or `r`. -/
def SideThin {V : Type u} (X : SimpleGraph V) (δ : ℕ) {x y z : V}
    (p : X.Walk x y) (q : X.Walk y z) (r : X.Walk z x) : Prop :=
  ∀ a ∈ p.support, ∃ b, (b ∈ q.support ∨ b ∈ r.support) ∧ X.dist a b ≤ δ

/-- A finitely generated group with a unit-edge Cayley graph whose geodesic triangles
are uniformly thin. Connectedness of this Cayley graph asserts that `S` generates. -/
def WordHyperbolic (G : Type u) [Group G] : Prop :=
  ∃ S : Set G, S.Finite ∧ (SimpleGraph.mulCayley S).Connected ∧
    ∃ δ : ℕ, ∀ (x y z : G)
      (p : (SimpleGraph.mulCayley S).Walk x y)
      (q : (SimpleGraph.mulCayley S).Walk y z)
      (r : (SimpleGraph.mulCayley S).Walk z x),
      Geodesic (SimpleGraph.mulCayley S) p →
      Geodesic (SimpleGraph.mulCayley S) q →
      Geodesic (SimpleGraph.mulCayley S) r →
      SideThin (SimpleGraph.mulCayley S) δ p q r ∧
      SideThin (SimpleGraph.mulCayley S) δ q r p ∧
      SideThin (SimpleGraph.mulCayley S) δ r p q

theorem main : ∃ (G : Type) (_ : Group G),
    TorsionFree G ∧ WordHyperbolic G ∧ ¬ Group.ResiduallyFinite G := by
  sorry

end Release075

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TorsionFreeHyperbolic.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Release075.main` must keep exactly the statement shown above: same names,
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
