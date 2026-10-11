# openai/math challenge `CourtadeKumar` (family 119)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 119 of the release, *The Courtade–Kumar and Hellinger conjectures*
(Theoretical computer science). The family as a whole: Proves the Courtade–Kumar conjecture: among Boolean functions of independent uniform bits, a single coordinate retains the most mutual information after independent bit-flip noise. A stronger theorem treats randomized binary summaries at fixed initial information. The Hellinger conjecture is also proved for every Boolean output bias and noise correlation.

The challenge is `CourtadeKumar`, also at `/opt/openai-math/challenges/CourtadeKumar.lean`:

```lean
import Mathlib

namespace OAI

open scoped BigOperators

namespace LeanBlast.GotsmanLinial

abbrev Cube (n : ℕ) := Fin n → Bool

end LeanBlast.GotsmanLinial

noncomputable section

open scoped BigOperators

namespace LeanBlast.CourtadeKumar

abbrev Cube (n : ℕ) := LeanBlast.GotsmanLinial.Cube n

def cubeAverage {n : ℕ} (g : Cube n → ℝ) : ℝ :=
  (∑ x, g x) / (2 : ℝ) ^ n

def ell : ℝ := Real.log 2

def bitFlipKernel {n : ℕ} (ε : ℝ) (x y : Cube n) : ℝ :=
  ∏ i, if x i = y i then 1 - ε else ε

def jointProbability {n : ℕ} (ε : ℝ) (f : Cube n → Bool) (b : Bool) (y : Cube n) : ℝ :=
  cubeAverage (fun x => if f x = b then bitFlipKernel ε x y else 0)

def functionMarginal {n : ℕ} (ε : ℝ) (f : Cube n → Bool) (b : Bool) : ℝ :=
  ∑ y, jointProbability ε f b y

def observationMarginal {n : ℕ} (ε : ℝ) (f : Cube n → Bool) (y : Cube n) : ℝ :=
  ∑ b : Bool, jointProbability ε f b y

def xlogx (t : ℝ) : ℝ := t * Real.log t

def binaryEntropy (ε : ℝ) : ℝ :=
  -(xlogx ε + xlogx (1 - ε)) / ell

def mutualInformation {n : ℕ} (ε : ℝ) (f : Cube n → Bool) : ℝ :=
  (∑ b : Bool, ∑ y : Cube n,
    if 0 < jointProbability ε f b y then
      jointProbability ε f b y *
        Real.log (jointProbability ε f b y /
          (functionMarginal ε f b * observationMarginal ε f y))
    else 0) / ell

def dictator {n : ℕ} (i : Fin n) (x : Cube n) : Bool := x i

def complementDictator {n : ℕ} (i : Fin n) (x : Cube n) : Bool := !(x i)

def CourtadeKumarStatement : Prop :=
  ∀ (n : ℕ), 1 ≤ n →
    ∀ ε : ℝ, 0 ≤ ε → ε ≤ (1 : ℝ) / 2 →
      ∀ f : Cube n → Bool, mutualInformation ε f ≤ 1 - binaryEntropy ε

def DictatorAttainmentStatement : Prop :=
  ∀ (n : ℕ), 1 ≤ n →
    ∀ ε : ℝ, 0 ≤ ε → ε ≤ (1 : ℝ) / 2 →
      ∀ i : Fin n,
        mutualInformation ε (dictator i) = 1 - binaryEntropy ε ∧
        mutualInformation ε (complementDictator i) = 1 - binaryEntropy ε

def FullStatement : Prop := CourtadeKumarStatement ∧ DictatorAttainmentStatement

theorem courtadeKumarAndAttainment : FullStatement := by
  sorry

end LeanBlast.CourtadeKumar

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CourtadeKumar.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LeanBlast.CourtadeKumar.courtadeKumarAndAttainment` must keep exactly the statement shown above: same names,
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
