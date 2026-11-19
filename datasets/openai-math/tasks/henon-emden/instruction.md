# openai/math challenge `HenonEmden` (family 370)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 370 of the release, *The subcritical Lane–Emden and Henon–Lane–Emden conjectures*
(Partial differential equations). The family as a whole: Resolves the subcritical Lane–Emden conjecture and its weighted Henon extension. For $n\ge2$, $p,q>0$ and real $A,B$, the system $-\Delta u=|x|^A v^p$, $-\Delta v=|x|^B u^q$ has no positive entire solution when $(n+A)/(p+1)+(n+B)/(q+1)>n-2$, with solutions continuous at the origin and classical elsewhere. No symmetry or growth assumption is needed. Known radial existence gives the exact existence criterion for $n\ge3$ and $A,B>-2$.

The challenge is `HenonEmden`, also at `/opt/openai-math/challenges/HenonEmden.lean`:

```lean
import Mathlib

namespace OAI

namespace HenonLaneEmden

abbrev Space (n : ℕ) := EuclideanSpace ℝ (Fin n)

structure IsSolution (n : ℕ) (p q A B : ℝ) (u v : Space n → ℝ) : Prop where
  continuous_u : Continuous u
  continuous_v : Continuous v
  regular_u : ContDiffOn ℝ 2 u ({0}ᶜ : Set (Space n))
  regular_v : ContDiffOn ℝ 2 v ({0}ᶜ : Set (Space n))
  positive_u : ∀ x, 0 < u x
  positive_v : ∀ x, 0 < v x
  equation_u : ∀ x, x ≠ 0 →
    -(Laplacian.laplacian u) x = Real.rpow ‖x‖ A * Real.rpow (v x) p
  equation_v : ∀ x, x ≠ 0 →
    -(Laplacian.laplacian v) x = Real.rpow ‖x‖ B * Real.rpow (u x) q

def Subcritical (n : ℕ) (p q A B : ℝ) : Prop :=
  ((n : ℝ) + A) / (p + 1) + ((n : ℝ) + B) / (q + 1) > (n : ℝ) - (1 + 1)

theorem main_nonexistence (n : ℕ) (hn : 2 ≤ n) (p q A B : ℝ)
    (hp : 0 < p) (hq : 0 < q) (hsub : Subcritical n p q A B) :
    ¬ ∃ u v : Space n → ℝ, IsSolution n p q A B u v := by
  sorry

end HenonLaneEmden

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/HenonEmden.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.HenonLaneEmden.main_nonexistence` must keep exactly the statement shown above: same names,
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
