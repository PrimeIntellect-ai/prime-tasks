# openai/math challenge `MatrixFields` (family 107)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 107 of the release, *Matrix multiplication with exponent at most $9/4$*
(Theoretical computer science). The family as a whole: Proves $\omega\le9/4$ over $\mathbb C$, giving $O_\varepsilon(n^{9/4+\varepsilon})$ arithmetic operations for square matrix multiplication. In characteristic zero, some inner dimension $n^a$ with $a>0.465$ permits $n^{2+o(1)}$ rectangular multiplication. Further square bounds give $\omega<2.258$ outside finitely many positive characteristics and $\omega<2.371054886006746$ over every fixed field.

The challenge is `MatrixFields`, also at `/opt/openai-math/challenges/MatrixFields.lean`:

```lean
import Mathlib

namespace OAI

open scoped BigOperators Topology Polynomial

namespace MatrixAllFields

noncomputable section

open scoped BigOperators

namespace MatrixMultiplication.Arithmetic

inductive Gate (F Input Register : Type*) where
  | constant : F → Gate F Input Register
  | input : Input → Gate F Input Register
  | add : Register → Register → Gate F Input Register
  | sub : Register → Register → Gate F Input Register
  | mul : Register → Register → Gate F Input Register

namespace Gate

variable {F Input Register : Type*}

def eval [Field F] (inputs : Input → F) (registers : Register → F) :
    Gate F Input Register → F
  | .constant z => z
  | .input i => inputs i
  | .add i j => registers i + registers j
  | .sub i j => registers i - registers j
  | .mul i j => registers i * registers j

def cost : Gate F Input Register → ℕ
  | .constant _ => 0
  | .input _ => 0
  | .add _ _ => 1
  | .sub _ _ => 1
  | .mul _ _ => 1

end Gate

inductive Program (F Input : Type*) : ℕ → Type _ where
  | nil : Program F Input 0
  | step {r : ℕ} : Program F Input r → Gate F Input (Fin r) → Program F Input (r + 1)

namespace Program

variable {F Input : Type*}

def eval [Field F] : {r : ℕ} → Program F Input r → (Input → F) → Fin r → F
  | 0, .nil, _ => Fin.elim0
  | _ + 1, .step p g, inputs =>
    Fin.cases (g.eval inputs (p.eval inputs)) (p.eval inputs)

def cost : {r : ℕ} → Program F Input r → ℕ
  | 0, .nil => 0
  | _ + 1, .step p g => p.cost + g.cost

end Program

abbrev MatrixInput (a b c : ℕ) := (Fin a × Fin b) ⊕ (Fin b × Fin c)

def matrixInputs {F : Type*} {a b c : ℕ}
    (A : Matrix (Fin a) (Fin b) F) (B : Matrix (Fin b) (Fin c) F) :
    MatrixInput a b c → F
  | .inl (i, j) => A i j
  | .inr (j, k) => B j k

structure MatrixAlgorithm (F : Type*) (a b c : ℕ) where
  registers : ℕ
  program : Program F (MatrixInput a b c) registers
  output : Fin a → Fin c → Fin registers

namespace MatrixAlgorithm

variable {F : Type*} [Field F] {a b c : ℕ}

def eval (P : MatrixAlgorithm F a b c)
    (A : Matrix (Fin a) (Fin b) F) (B : Matrix (Fin b) (Fin c) F) :
    Matrix (Fin a) (Fin c) F :=
  fun i k => P.program.eval (matrixInputs A B) (P.output i k)

def Correct (P : MatrixAlgorithm F a b c) : Prop :=
  ∀ (A : Matrix (Fin a) (Fin b) F) (B : Matrix (Fin b) (Fin c) F), P.eval A B = A * B

def cost (P : MatrixAlgorithm F a b c) : ℕ := P.program.cost

end MatrixAlgorithm

/-- Positive slack, one uniform constant, and a correct program at every size. -/
def AdmissibleExponent (F : Type*) [Field F] (τ : ℝ) : Prop :=
  ∀ ε : ℝ, 0 < ε → ∃ C : ℝ, 0 < C ∧
    ∀ n : ℕ, 1 ≤ n → ∃ P : MatrixAlgorithm F n n n,
      P.Correct ∧ (P.cost : ℝ) ≤ C * (n : ℝ) ^ (τ + ε)

def omega (F : Type*) [Field F] : ℝ := sInf {τ : ℝ | AdmissibleExponent F τ}

end MatrixMultiplication.Arithmetic

end

end MatrixAllFields

namespace MatrixAllFields.MatrixMultiplication.AllFieldMain

universe u

theorem omega_lt_source_constant (F : Type u) [Field F] :
    Arithmetic.omega F < (2371054886006746 : ℝ) / 10 ^ 15 ∧
    (2371054886006746 : ℝ) / 10 ^ 15 < (2371056 : ℝ) / 10 ^ 6 := by
  sorry

end MatrixAllFields.MatrixMultiplication.AllFieldMain

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MatrixFields.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.MatrixAllFields.MatrixMultiplication.AllFieldMain.omega_lt_source_constant` must keep exactly the statement shown above: same names,
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
