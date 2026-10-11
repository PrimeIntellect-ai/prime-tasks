# openai/math challenge `ComplexCancellation` (family 047)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 047 of the release, *Complex counterexamples to cancellation and affine fibrations*
(Algebraic and complex geometry). The family as a whole: Constructs an integral complex affine fourfold $X\not\cong\mathbb A^4$ with $X\times\mathbb A^1\cong\mathbb A^5$, disproving affine-space cancellation over $\mathbb C$ in dimension four. It also disproves the Dolgachev–Weisfeiler affine-fibration conjecture: smooth surjections $X\to\mathbb A^1$ and $\mathbb A^5\to\mathbb A^2$ have every residue-field fiber isomorphic to affine three-space but are not Zariski-locally trivial.

The challenge is `ComplexCancellation`, also at `/opt/openai-math/challenges/ComplexCancellation.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace ComplexCancellation

abbrev P := MvPolynomial (Fin 5) ℂ

def p : P := MvPolynomial.X 0
def s : P := MvPolynomial.X 1
def u : P := MvPolynomial.X 2
def F : P := MvPolynomial.X 3
def J : P := MvPolynomial.X 4
def x : P := s ^ 2 + u ^ 3 + p ^ 2 * F
def H : P := x ^ 2 * F - (1 + 2 * s * x) * J - p ^ 2 * J ^ 2 - p * u
abbrev A := P ⧸ Ideal.span {H}

def MainStatement : Prop :=
  Algebra.FiniteType ℂ A ∧ IsDomain A ∧ ringKrullDim A = 4 ∧
  Nonempty (Polynomial A ≃ₐ[ℂ] MvPolynomial (Fin 5) ℂ) ∧
  ¬ Nonempty (A ≃ₐ[ℂ] MvPolynomial (Fin 4) ℂ)

theorem main : MainStatement := by
  sorry

end ComplexCancellation

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ComplexCancellation.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ComplexCancellation.main` must keep exactly the statement shown above: same names,
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
