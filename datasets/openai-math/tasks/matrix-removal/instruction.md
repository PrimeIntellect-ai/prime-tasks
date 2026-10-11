# openai/math challenge `MatrixRemoval` (family 190)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 190 of the release, *Polynomial removal fails for ordered binary matrices*
(Combinatorics). The family as a whole: Disproves polynomial ordered binary matrix removal with one fixed $66\times66$ zero–one pattern. Matrices can require many binary-entry changes to become pattern-free while their copy density is smaller than every proposed polynomial bound in that distance. Copies preserve row and column orders and match both zeros and ones.

The challenge is `MatrixRemoval`, also at `/opt/openai-math/challenges/MatrixRemoval.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace Problem348

abbrev BinaryMatrix (n : ℕ) := Fin n → Fin n → Bool

abbrev IncreasingMap (k n : ℕ) := {f : Fin k → Fin n // StrictMono f}

def orderedCopies {k n : ℕ} (H : BinaryMatrix k) (A : BinaryMatrix n) :
    Finset (IncreasingMap k n × IncreasingMap k n) := by
  classical
  exact Finset.univ.filter (fun rc =>
    ∀ i j, A ((rc.1).val i) ((rc.2).val j) = H i j)

def copyCount {k n : ℕ} (H : BinaryMatrix k) (A : BinaryMatrix n) : ℕ :=
  (orderedCopies H A).card

def HFree {k n : ℕ} (H : BinaryMatrix k) (A : BinaryMatrix n) : Prop :=
  copyCount H A = 0

def hammingDistance {n : ℕ} (A B : BinaryMatrix n) : ℕ := by
  classical
  exact (Finset.univ.filter (fun rc : Fin n × Fin n =>
    A rc.1 rc.2 ≠ B rc.1 rc.2)).card

def etaBit (a b : ℕ) : Bool :=
  decide (((a / (2 ^ (5 - b))) % 2) = 1)

def anchor64 (u v : Fin 64) : Bool :=
  if 32 ≤ u.val ∧ 59 ≤ v.val then
    etaBit (u.val - 32) (v.val - 58)
  else
    decide (u.val ≠ v.val)

def fixedH : BinaryMatrix 66 := fun u v =>
  if hu : u.val < 64 then
    if hv : v.val < 64 then
      anchor64 ⟨u.val, hu⟩ ⟨v.val, hv⟩
    else
      decide ((v.val = 64 ∧ u.val = 0) ∨
        (v.val = 65 ∧ u.val = 1))
  else
    if v.val < 64 then
      decide ((u.val = 64 ∧ v.val = 0) ∨
        (u.val = 65 ∧ v.val = 1))
    else
      decide (u.val = 65 ∨ v.val = 64)

def fixedMinEdits {n : ℕ} (A : BinaryMatrix n) : ℕ := by
  classical
  exact
    (Finset.univ.image (fun B : BinaryMatrix n =>
      if HFree fixedH B then hammingDistance A B else n * n + 1)).min'
      (by simp)

def fixedDistance {n : ℕ} (A : BinaryMatrix n) : ℝ :=
  (fixedMinEdits A : ℝ) / ((n : ℝ) ^ 2)

theorem no_polynomial_removal_bound :
    ∀ c C : ℝ, 0 < c → 0 < C →
  ∃ n : ℕ, 1 ≤ n ∧
    ∃ ε : ℝ, 0 < ε ∧ ε < 1 ∧
      ∃ A : BinaryMatrix n,
        fixedDistance A ≥ ε ∧
        (copyCount fixedH A : ℝ) <
          c * Real.rpow ε C * ((n : ℝ) ^ 132) := by
  sorry

end Problem348

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MatrixRemoval.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Problem348.no_polynomial_removal_bound` must keep exactly the statement shown above: same names,
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
