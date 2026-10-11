# openai/math challenge `GaussianMoat` (family 028)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 028 of the release, *The Gaussian moat conjecture*
(Number theory). The family as a whole: Proves the Gaussian moat conjecture: no infinite walk through distinct Gaussian primes can have uniformly bounded steps. More strongly, for every distance bound $D$, the graph joining Gaussian primes at distance at most $D$ has uniformly bounded finite component sizes, depending only on $D$, including primes on the coordinate axes.

The challenge is `GaussianMoat`, also at `/opt/openai-math/challenges/GaussianMoat.lean`:

```lean
import Mathlib

namespace OAI

namespace GaussianMoat

abbrev PrimeVertex := {z : GaussianInt // Irreducible z}

noncomputable def primeGraph (D : ℝ) : SimpleGraph PrimeVertex where
  Adj p q := p ≠ q ∧ dist (p.val : ℂ) (q.val : ℂ) ≤ D
  symm := by
    constructor
    intro p q h
    exact ⟨h.1.symm, by simpa only [dist_comm] using h.2⟩
  loopless := by
    constructor
    intro p h
    exact h.1 rfl

def component (D : ℝ) (p : PrimeVertex) : Set PrimeVertex :=
  {q | (primeGraph D).Reachable p q}

def MainEndpoint : Prop :=
  ∀ (D : ℝ) (z : ℕ → GaussianInt),
    (∀ t, Irreducible (z t)) → Function.Injective z →
    (∀ t, dist (z (t + 1) : ℂ) (z t : ℂ) ≤ D) → False

def UniformEndpoint : Prop :=
  ∀ D : ℝ, ∃ B : ℕ,
    (∀ p : PrimeVertex, (component D p).Finite ∧ (component D p).ncard ≤ B) ∧
    (∀ (n : ℕ) (z : Fin n → GaussianInt),
      (∀ i, Irreducible (z i)) → Function.Injective z →
      (∀ i j : Fin n, j.val = i.val + 1 → dist (z j : ℂ) (z i : ℂ) ≤ D) →
      n ≤ B)

theorem fullMain : MainEndpoint ∧ UniformEndpoint := by
  sorry

end GaussianMoat

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/GaussianMoat.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.GaussianMoat.fullMain` must keep exactly the statement shown above: same names,
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
