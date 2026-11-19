# openai/math challenge `QACParity` (family 274)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 274 of the release, *Moore's parity conjecture for $\mathrm{QAC}^0$*
(Mathematical physics). The family as a whole: Resolves Moore's parity conjecture in the measured-output model: constant-depth quantum circuits with arbitrary one-qubit gates, unbounded-arity Toffoli gates and polynomially many total qubits cannot compute parity with any fixed positive worst-case advantage. Ancillas start in zero, one output qubit is measured, and all other registers may be discarded. Xu–Li's reductions give the same bounded-error obstruction for strict majority.

The challenge is `QACParity`, also at `/opt/openai-math/challenges/QACParity.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators Matrix.Norms.L2Operator

namespace QAC

abbrev Bit := Fin 2
abbrev Word (N : ℕ) := Fin N → Bit
abbrev Operator (N : ℕ) := Matrix (Word N) (Word N) ℂ
abbrev QubitOperator := Matrix Bit Bit ℂ

/-- Tensor product in the computational basis. -/
def tensorMatrix {N : ℕ} (a : Fin N → QubitOperator) : Operator N :=
  fun x y => ∏ i, a i (x i) (y i)

/-- A one-qubit unitary or an unbounded-arity Toffoli gate. -/
inductive Gate (N : ℕ) where
  | local (q : Fin N) (u : Matrix.unitaryGroup Bit ℂ)
  | toffoli (controls : Finset (Fin N)) (target : Fin N) (hne : target ∉ controls)

namespace Gate

def support {N : ℕ} : Gate N → Finset (Fin N)
  | .local q _ => {q}
  | .toffoli c t _ => insert t c

/-- A Toffoli flips its target iff all controls are one. -/
def toffoliWord {N : ℕ} (c : Finset (Fin N)) (t : Fin N) (x : Word N) : Word N :=
  if ∀ i ∈ c, x i = 1 then Function.update x t (1 - x t) else x

def matrix {N : ℕ} : Gate N → Operator N
  | .local q u => tensorMatrix fun i => if i = q then (u : QubitOperator) else 1
  | .toffoli c t _ => fun x y => if x = toffoliWord c t y then 1 else 0

end Gate

structure PhysicalLayer (N : ℕ) where
  gates : List (Gate N)
  disjoint : gates.Pairwise (fun A B => Disjoint A.support B.support)

def physicalLayerMatrix {N : ℕ} (L : PhysicalLayer N) : Operator N :=
  (L.gates.map Gate.matrix).prod

/-- Chronological order: the rightmost matrix acts first. -/
def physicalCircuitMatrix {N : ℕ} (layers : List (PhysicalLayer N)) : Operator N :=
  ((layers.map physicalLayerMatrix).reverse).prod

/-- The computational-basis input with the remaining qubits initialized to zero. -/
def inputWord {n N : ℕ} (x : Word n) : Word N :=
  fun i => if h : i.val < n then x ⟨i.val, h⟩ else 0

def parity {n : ℕ} (x : Word n) : Bit := ∑ i, x i

/-- Born probability, summing all final garbage with no cleanliness assumption. -/
def successProbability {n N : ℕ} (W : Operator N) (out : Fin N) (x : Word n) : ℝ :=
  ∑ y : Word N, if y out = parity x then Complex.normSq (W y (inputWord x)) else 0

/-- The literal measured-output, polynomial-total-qubit parity lower bound. -/
def ParityStatement : Prop :=
  ∀ (d : ℕ) (c ε : ℝ), 1 ≤ c → 0 < ε → ε ≤ 1 / 2 →
    ∃ n₀ : ℕ, ∀ n ≥ n₀, ∀ N : ℕ, n ≤ N → (N : ℝ) ≤ (n : ℝ) ^ c →
      ∀ layers : List (PhysicalLayer N), layers.length ≤ d →
        ∀ out : Fin N, ¬ (∀ x : Word n,
          1 / 2 + ε ≤ successProbability (physicalCircuitMatrix layers) out x)

end QAC

theorem QAC.parity_lower_bound : QAC.ParityStatement := by
  sorry

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/QACParity.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.QAC.parity_lower_bound` must keep exactly the statement shown above: same names,
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
