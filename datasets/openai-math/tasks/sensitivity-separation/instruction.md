# openai/math challenge `SensitivitySeparation` (family 132)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 132 of the release, *A counterexample to the quadratic sensitivity conjecture*
(Theoretical computer science). The family as a whole: Constructs total Boolean functions with block sensitivity $\operatorname{bs}(f)\ge s(f)^\alpha$ for a fixed $\alpha>2$, disproving the quadratic strengthening of the Sensitivity Conjecture. Here $s(f)$ counts influential individual-bit flips, while block sensitivity allows disjoint groups of bits to change together.

The challenge is `SensitivitySeparation`, also at `/opt/openai-math/challenges/SensitivitySeparation.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped Classical

namespace Paper320

def flip {I : Type} (x : I → Bool) (B : Finset I) : I → Bool :=
  fun i => if i ∈ B then !(x i) else x i

def sensitivityAt {I : Type} [Fintype I]
    (f : (I → Bool) → Bool) (x : I → Bool) : ℕ :=
  (Finset.univ.filter fun i => f (flip x {i}) ≠ f x).card

def sensitivity {I : Type} [Fintype I] (f : (I → Bool) → Bool) : ℕ :=
  Finset.univ.sup (sensitivityAt f)

def blockSensitivityAt {I : Type} [Fintype I]
    (f : (I → Bool) → Bool) (x : I → Bool) : ℕ :=
  Finset.univ.sup fun blocks : Finset (Finset I) =>
    if (∀ A ∈ blocks, ∀ B ∈ blocks, A ≠ B → Disjoint A B) ∧
        (∀ B ∈ blocks, B.Nonempty ∧ f (flip x B) ≠ f x)
    then blocks.card else 0

def blockSensitivity {I : Type} [Fintype I] (f : (I → Bool) → Bool) : ℕ :=
  Finset.univ.sup (blockSensitivityAt f)

theorem quantitative_separation (d : ℕ) (hd : 1 ≤ d) :
    ∃ (n : ℕ) (f : (Fin n → Bool) → Bool),
      0 < n ∧ f (fun _ => false) = false ∧
      (∃ x y : Fin n → Bool, f x ≠ f y) ∧
      (2 : ℝ) ^ d / (4 * ((d : ℝ) + 2) ^ 2) ≤
        (blockSensitivity f : ℝ) / (sensitivity f : ℝ) ^ 2 := by
  sorry

end Paper320

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SensitivitySeparation.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Paper320.quantitative_separation` must keep exactly the statement shown above: same names,
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
