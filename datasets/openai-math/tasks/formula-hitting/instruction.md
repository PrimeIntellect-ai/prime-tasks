# openai/math challenge `FormulaHitting` (family 116)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 116 of the release, *Uniform identity testing for noncommutative formulas*
(Theoretical computer science). The family as a whole: For each characteristic, constructs in deterministic polynomial bit time a polynomial-dimensional matrix tuple detecting every nonzero division-free noncommutative formula of bounded size over any field of that characteristic. Rational formulas over $\mathbb Q$ also admit polynomial-size hitting lists whenever they have a defined rational-matrix evaluation.

The challenge is `FormulaHitting`, also at `/opt/openai-math/challenges/FormulaHitting.lean`:

```lean
import Mathlib.Data.Matrix.Basic
import Mathlib.Data.Rat.Defs

namespace OAI

namespace NCHitting

abbrev Word (n : ℕ) := List (Fin n)
abbrev WordSeries (F : Type*) (n : ℕ) := Word n → F

def convolution {F : Type*} {n : ℕ} [Semiring F]
    (f g : WordSeries F n) : Word n → F
  | [] => f [] * g []
  | i :: w => f [] * g (i :: w) + convolution (fun v => f (i :: v)) g w

inductive Formula (F : Type*) (n : ℕ) where
  | scalar : F → Formula F n
  | var : Fin n → Formula F n
  | add : Formula F n → Formula F n → Formula F n
  | mul : Formula F n → Formula F n → Formula F n

namespace Formula

def size {F : Type*} {n : ℕ} : Formula F n → ℕ
  | scalar _ => 1
  | var _ => 1
  | add f g => f.size + g.size + 1
  | mul f g => f.size + g.size + 1

noncomputable def coeff {F : Type*} {n : ℕ} [Semiring F] :
    Formula F n → WordSeries F n
  | scalar a => fun w => if w = [] then a else 0
  | var i => fun w => if w = [i] then 1 else 0
  | add f g => fun w => coeff f w + coeff g w
  | mul f g => convolution (coeff f) (coeff g)

def eval {F A : Type*} {n : ℕ} [Semiring A]
    (scalarMap : F → A) (T : Fin n → A) : Formula F n → A
  | scalar a => scalarMap a
  | var i => T i
  | add f g => eval scalarMap T f + eval scalarMap T g
  | mul f g => eval scalarMap T f * eval scalarMap T g

end Formula

def dimension (n s : ℕ) : ℕ := if n = 1 ∧ s = 1 then 1 else 2 * n * s ^ 2

def matrixEntry (i r q : ℕ) : ℚ :=
  if q < r then (-1 : ℚ) ^ (r - q - 1) / ((r : ℚ) * (i : ℚ) ^ (r - q))
  else 0

def generator (n s : ℕ) : Fin n → Matrix (Fin (dimension n s)) (Fin (dimension n s)) ℚ :=
  fun i r q => if n = 1 ∧ s = 1 then 1 else matrixEntry (i.val + 1) r.val q.val

universe u_2

theorem universal_hitting (n s : ℕ) (hn : 1 ≤ n) (hs : 1 ≤ s)
    (F : Type u_2) [Field F] [CharZero F] (f : Formula F n)
    (hsize : f.size ≤ s) (hf : ∃ w, f.coeff w ≠ 0) :
    f.eval (Matrix.scalar (Fin (dimension n s)))
      (fun i r q => (generator n s i r q : F)) ≠ 0 := by
  sorry

end NCHitting

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/FormulaHitting.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.NCHitting.universal_hitting` must keep exactly the statement shown above: same names,
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
