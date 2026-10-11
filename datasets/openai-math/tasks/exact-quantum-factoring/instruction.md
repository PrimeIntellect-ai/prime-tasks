# openai/math challenge `ExactQuantumFactoring` (family 279)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 279 of the release, *Exact quantum factoring over a fixed finite gate set*
(Mathematical physics). The family as a whole: Gives a polynomial-time uniform quantum circuit family that outputs the complete prime factorization of every integer with probability one. Both gate count and qubit count are polynomial in the input length, and one fixed finite gate set suffices.

The challenge is `ExactQuantumFactoring`, also at `/opt/openai-math/challenges/ExactQuantumFactoring.lean`:

```lean
import Mathlib

namespace OAI



namespace ExactQuantumFactoring

open scoped BigOperators

/-- The five primitive gates exactly as in Section 2. -/
inductive Primitive where
  | not | cnot | toffoli | hadamard | phase
  deriving DecidableEq

def Primitive.arity : Primitive → ℕ
  | .not | .hadamard | .phase => 1
  | .cnot => 2
  | .toffoli => 3

def Primitive.code : Primitive → ℕ
  | .not => 0 | .cnot => 1 | .toffoli => 2 | .hadamard => 3 | .phase => 4

/-- An inverse and/or one added control. This is a fixed set of 20 gate names,
not an unbounded-control or arbitrary-angle gate model. -/
structure Gate where
  primitive : Primitive
  inverse : Bool
  controlled : Bool
  deriving DecidableEq

def Gate.arity (g : Gate) : ℕ := g.primitive.arity + if g.controlled then 1 else 0

/-- Matrix entries are indexed by lists in wire order (row first, column second).
Entries on ill-sized lists are irrelevant and set to zero. -/
noncomputable def Primitive.matrix : Primitive → List Bool → List Bool → ℂ
  | .not, [a], [b] => if a = !b then 1 else 0
  | .cnot, [a,b], [c,d] => if a = c ∧ b = Bool.xor c d then 1 else 0
  | .toffoli, [a,b,c], [d,e,f] =>
      if a = d ∧ b = e ∧ c = Bool.xor f (d && e) then 1 else 0
  | .hadamard, [a], [b] =>
      (if a && b then -1 else 1) / (Real.sqrt 2 : ℂ)
  | .phase, [a], [b] => if a = b then (if b then Complex.I else 1) else 0
  | _, _, _ => 0

noncomputable def Gate.baseMatrix (g : Gate) (a b : List Bool) : ℂ :=
  if g.inverse then star (g.primitive.matrix b a) else g.primitive.matrix a b

noncomputable def Gate.matrix (g : Gate) (a b : List Bool) : ℂ :=
  if g.controlled then
    match a, b with
    | false :: a', false :: b' => if a' = b' then 1 else 0
    | true :: a', true :: b' => g.baseMatrix a' b'
    | _, _ => 0
  else g.baseMatrix a b

/-- A primitive is placed on distinct actual wires, with no operation of
unbounded arity hidden in a circuit instruction. -/
structure Instruction (q : ℕ) where
  gate : Gate
  wire : Fin gate.arity → Fin q
  distinct : Function.Injective wire

abbrev Basis (q : ℕ) := Fin q → Bool
abbrev State (q : ℕ) := Basis q → ℂ

noncomputable def Instruction.matrix {q : ℕ} (o : Instruction q) :
    Matrix (Basis q) (Basis q) ℂ := by
  classical
  exact fun a b =>
    if ∀ i : Fin q, (∀ j, o.wire j ≠ i) → a i = b i then
      o.gate.matrix (List.ofFn (a ∘ o.wire)) (List.ofFn (b ∘ o.wire))
    else 0

structure Circuit where
  qubits : ℕ
  instructions : List (Instruction qubits)

noncomputable def Circuit.apply (c : Circuit) (ψ : State c.qubits) : State c.qubits :=
  c.instructions.foldl (fun v o => o.matrix.mulVec v) ψ

/-- Input wires are first, least significant bit first; all other wires start zero. -/
def inputBasis (q ℓ N : ℕ) : Basis q :=
  fun i => if i.val < ℓ then N.testBit i.val else false

noncomputable def Circuit.outputState (c : Circuit) (ℓ N : ℕ) : State c.qubits := by
  classical
  exact c.apply (fun x => if x = inputBasis c.qubits ℓ N then 1 else 0)

/-- The cutoff and padding are the standing parameters in Section 2. -/
def paddedLength (ℓ : ℕ) : ℕ := max 128 ℓ

def readBit {q : ℕ} (x : Basis q) (i : ℕ) : Bool :=
  if h : i < q then x ⟨i,h⟩ else false

/-- n entries of n bits each, in the n² wires immediately after the input. -/
def outputList {q : ℕ} (ℓ : ℕ) (x : Basis q) : List ℕ :=
  let n := paddedLength ℓ
  List.ofFn (fun a : Fin n =>
    ∑ j ∈ Finset.range n, if readBit x (ℓ + a.val * n + j) then 2^j else 0)

/-- Complete nondecreasing prime factorization, multiplicities included,
padded by zeros, as in Section 6. There is no primality oracle in the circuit. -/
def CorrectEncoding (N n : ℕ) (xs : List ℕ) : Prop :=
  ∃ ps : List ℕ, (∀ p ∈ ps, Nat.Prime p) ∧ ps.Pairwise (· ≤ ·) ∧
    ps.prod = N ∧ ps.length ≤ n ∧ xs = ps ++ List.replicate (n - ps.length) 0

/-- Unnormalized Born sum on correct outputs; success is exactly one,
not positivity, postselection, or a limiting high probability. -/
noncomputable def Circuit.correctProbability (c : Circuit) (ℓ N : ℕ) : ℝ := by
  classical
  exact ∑ x : Basis c.qubits,
    if CorrectEncoding N (paddedLength ℓ) (outputList ℓ x) then
      Complex.normSq (c.outputState ℓ N x) else 0

/-- Unary natural words with delimiters make the circuit description explicit.
Unary wire addresses cause at most polynomial overhead when width is polynomial. -/
def natWord (k : ℕ) : List Bool := List.replicate k true ++ [false]

def Instruction.encode {q : ℕ} (o : Instruction q) : List Bool :=
  natWord o.gate.primitive.code ++ [o.gate.inverse, o.gate.controlled] ++
    (List.ofFn (fun i => o.wire i |>.val)).flatMap natWord

def Circuit.encode (c : Circuit) : List Bool :=
  natWord c.qubits ++ natWord c.instructions.length ++
    c.instructions.flatMap Instruction.encode

/-- A single finite-alphabet classical generator receives only the INPUT LENGTH.
All stack alphabets, states and labels are finite: no large-integer unit-cost
oracle is hidden in TM2 push/branch functions. -/
def Uniform (family : ℕ → Circuit) : Prop :=
  ∃ generator : Turing.TM2ComputableInPolyTime
      (fun ℓ => List.replicate ℓ true) Circuit.encode family,
    ∀ k, Finite (generator.tm.Γ k)

def PolynomialResources (family : ℕ → Circuit) : Prop :=
  ∃ bound : Polynomial ℕ, ∀ ℓ,
    (family ℓ).qubits ≤ bound.eval ℓ ∧
    (family ℓ).instructions.length ≤ bound.eval ℓ

/-- Literal main endpoint: one length-uniform family, exact output for EVERY
binary integer N≥2, and worst-case polynomial gates AND qubits. -/
def MainTheorem : Prop :=
  ∃ family : ℕ → Circuit, Uniform family ∧ PolynomialResources family ∧
    ∀ (ℓ N : ℕ), 2 ≤ N → N.size = ℓ →
      ℓ + (paddedLength ℓ)^2 ≤ (family ℓ).qubits ∧
      (family ℓ).correctProbability ℓ N = 1

theorem exact_quantum_factoring : MainTheorem := by
  sorry

end ExactQuantumFactoring

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ExactQuantumFactoring.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ExactQuantumFactoring.exact_quantum_factoring` must keep exactly the statement shown above: same names,
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
