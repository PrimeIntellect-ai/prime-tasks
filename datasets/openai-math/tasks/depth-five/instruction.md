# openai/math challenge `DepthFive` (family 135)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 135 of the release, *Sharp homogeneous depth-five complexity of matrix products*
(Theoretical computer science). The family as a whole: Over every characteristic-zero field, the $(1,1)$ entry of a product of $n$ independent $n\times n$ variable matrices requires $n^{\Theta(\sqrt n)}$ gates in homogeneous depth-five sum–product circuits. This sharp bound allows shared gates and bottom linear forms involving all variables.

The challenge is `DepthFive`, also at `/opt/openai-math/challenges/DepthFive.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

open scoped BigOperators
universe u

namespace Problem335

inductive D5Leaf (K : Type u) (n : ℕ) where
  | scalar : K → D5Leaf K n
  | variable : (Fin n × Fin n × Fin n) → D5Leaf K n

def d5LeafDegree {K : Type u} {n : ℕ} : D5Leaf K n → ℕ
  | D5Leaf.scalar _ => 0
  | D5Leaf.variable _ => 1

structure Depth5Circuit (K : Type u) [CommSemiring K] (n : ℕ) where
  leafCount : ℕ
  leaves : Fin leafCount → D5Leaf K n
  bottomCount : ℕ
  bottomInputs : Fin bottomCount → List (K × Fin leafCount)
  bottomDegree : Fin bottomCount → ℕ
  bottomHomogeneous :
    ∀ i entry, entry ∈ bottomInputs i → d5LeafDegree (leaves entry.2) = bottomDegree i
  bottomEmpty :
    ∀ i, bottomInputs i = [] → bottomDegree i = 0
  lowerCount : ℕ
  lowerInputs : Fin lowerCount → List (Fin bottomCount)
  middleCount : ℕ
  middleInputs : Fin middleCount → List (K × Fin lowerCount)
  middleDegree : Fin middleCount → ℕ
  middleHomogeneous :
    ∀ i entry, entry ∈ middleInputs i →
      ((lowerInputs entry.2).map bottomDegree).sum = middleDegree i
  middleEmpty :
    ∀ i, middleInputs i = [] → middleDegree i = 0
  upperCount : ℕ
  upperInputs : Fin upperCount → List (Fin middleCount)
  outputInputs : List (K × Fin upperCount)
  outputDegree : ℕ
  outputHomogeneous :
    ∀ entry, entry ∈ outputInputs →
      ((upperInputs entry.2).map middleDegree).sum = outputDegree
  outputEmpty :
    outputInputs = [] → outputDegree = 0

def d5LeafValue {K : Type u} [CommSemiring K] {n : ℕ}
    (x : D5Leaf K n) : MvPolynomial (Fin n × Fin n × Fin n) K :=
  match x with
  | D5Leaf.scalar a => MvPolynomial.C a
  | D5Leaf.variable i => MvPolynomial.X i

def bottomValue {K : Type u} [CommSemiring K] {n : ℕ}
    (c : Depth5Circuit K n) (i : Fin c.bottomCount) :
    MvPolynomial (Fin n × Fin n × Fin n) K := by
  classical
  exact ((c.bottomInputs i).map (fun entry =>
    MvPolynomial.C entry.1 * d5LeafValue (c.leaves entry.2))).sum

def lowerValue {K : Type u} [CommSemiring K] {n : ℕ}
    (c : Depth5Circuit K n) (i : Fin c.lowerCount) :
    MvPolynomial (Fin n × Fin n × Fin n) K := by
  classical
  exact ((c.lowerInputs i).map (fun j => bottomValue c j)).prod

def middleValue {K : Type u} [CommSemiring K] {n : ℕ}
    (c : Depth5Circuit K n) (i : Fin c.middleCount) :
    MvPolynomial (Fin n × Fin n × Fin n) K := by
  classical
  exact ((c.middleInputs i).map (fun entry =>
    MvPolynomial.C entry.1 * lowerValue c entry.2)).sum

def upperValue {K : Type u} [CommSemiring K] {n : ℕ}
    (c : Depth5Circuit K n) (i : Fin c.upperCount) :
    MvPolynomial (Fin n × Fin n × Fin n) K := by
  classical
  exact ((c.upperInputs i).map (fun j => middleValue c j)).prod

def circuitValue {K : Type u} [CommSemiring K] {n : ℕ}
    (c : Depth5Circuit K n) : MvPolynomial (Fin n × Fin n × Fin n) K := by
  classical
  exact (c.outputInputs.map (fun entry =>
    MvPolynomial.C entry.1 * upperValue c entry.2)).sum

def circuitSize {K : Type u} [CommSemiring K] {n : ℕ}
    (c : Depth5Circuit K n) : ℕ :=
  c.leafCount + c.bottomCount + c.lowerCount + c.middleCount + c.upperCount + 1

def immLayer (K : Type u) [CommSemiring K] (n : ℕ) (t : Fin n) :
    Matrix (Fin n) (Fin n) (MvPolynomial (Fin n × Fin n × Fin n) K) :=
  fun i j => MvPolynomial.X (t, i, j)

def imm (K : Type u) [CommSemiring K] (n : ℕ) :
    MvPolynomial (Fin n × Fin n × Fin n) K := by
  classical
  by_cases h : 0 < n
  · let matrices :
        List (Matrix (Fin n) (Fin n)
          (MvPolynomial (Fin n × Fin n × Fin n) K)) :=
      List.ofFn (fun t : Fin n => immLayer K n t)
    exact matrices.prod ⟨0, h⟩ ⟨0, h⟩
  · exact 0

def ceilSqrt (n : ℕ) : ℕ :=
  Nat.sqrt n + if (Nat.sqrt n) ^ 2 = n then 0 else 1

def ceilDiv (n t : ℕ) : ℕ :=
  (n + t - 1) / t

def upperGateBound (n : ℕ) : ℕ :=
  let t := ceilSqrt n
  let r := ceilDiv n t
  2 * n ^ 3 + r * n ^ 2 + r * n ^ (t + 1) + n ^ (r - 1) + 1

theorem main :
    (∃ threshold : ℕ, ∀ size : ℕ, threshold ≤ size →
      ∀ circuit : Depth5Circuit ℂ size, circuitValue circuit = imm ℂ size →
        (size : ℝ) ^ (Real.sqrt (size : ℝ) / 400) ≤ (circuitSize circuit : ℝ)) ∧
    (∃ threshold : ℕ, ∀ (FieldType : Type u) [Field FieldType] [CharZero FieldType],
      ∀ size : ℕ, threshold ≤ size → ∀ circuit : Depth5Circuit FieldType size,
        circuitValue circuit = imm FieldType size →
          (size : ℝ) ^ (Real.sqrt (size : ℝ) / 400) ≤ (circuitSize circuit : ℝ)) ∧
    (∀ (FieldType : Type u) [Field FieldType] (size : ℕ), 2 ≤ size →
      ∃ circuit : Depth5Circuit FieldType size, circuitValue circuit = imm FieldType size ∧
        circuitSize circuit ≤ upperGateBound size ∧
        (upperGateBound size : ℝ) ≤ (size : ℝ) ^ (Real.sqrt (size : ℝ) + 4)) := by
  sorry

end Problem335

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DepthFive.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Problem335.main` must keep exactly the statement shown above: same names,
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
