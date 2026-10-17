# openai/math challenge `CommonBasesFPRAS` (family 114)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 114 of the release, *Approximate counting of common integer polymatroid bases*
(Theoretical computer science). The family as a whole: Gives a fully polynomial randomized approximation scheme for counting common integer bases of two integral polymatroids of equal total rank, supplied by exact rank-value oracles. Capacities are binary-encoded, each integer vector counts once, and oracle calls and bit operations outside the oracles are polynomial on every execution. For matroids presented by independence oracles, the results also cover common independent sets of prescribed, unrestricted, or maximum cardinality, even when the ranks differ.

The challenge is `CommonBasesFPRAS`, also at `/opt/openai-math/challenges/CommonBasesFPRAS.lean`:

```lean
import Mathlib

namespace OAI

namespace CommonBasesFPRAS

abbrev IndependenceOracle (n : ℕ) := Bool → (Fin n → Bool) → Bool

def ExactOracles {n : ℕ} (M₁ M₂ : Matroid (Fin n))
    (O : IndependenceOracle n) : Prop :=
  ∀ (which : Bool) (A : Fin n → Bool),
    O which A = true ↔ (if which then M₂ else M₁).Indep {i | A i = true}

noncomputable def commonBaseCount {n : ℕ} (M₁ M₂ : Matroid (Fin n)) : ℕ :=
  Nat.card {A : Finset (Fin n) // M₁.IsBase (A : Set (Fin n)) ∧
    M₂.IsBase (A : Set (Fin n))}

inductive Instruction (k s : ℕ) where
  | push (register : Fin (k + 8)) (bit : Bool) (next : Fin (s + 1))
  | pop (register : Fin (k + 8)) (empty zero one : Fin (s + 1))
  | coin (zero one : Fin (s + 1))
  | query (which : Bool) (register : Fin (k + 8)) (no yes : Fin (s + 1))
  | halt

def Program (k s : ℕ) := Fin (s + 1) → Instruction k s

def binaryValue : List Bool → ℕ
  | [] => 0
  | b :: l => (if b then 1 else 0) + 2 * binaryValue l

structure MachineConfig (k s : ℕ) where
  registers : Fin (k + 8) → List Bool
  control : Fin (s + 1)
  output : Option ℚ := none
  oracleCalls : ℕ := 0
  bitOperations : ℕ := 0

def inputLength (n r : ℕ) (ε δ : ℚ) : ℕ :=
  6 + n.bits.length + r.bits.length + ε.num.natAbs.bits.length + ε.den.bits.length +
    δ.num.natAbs.bits.length + δ.den.bits.length

def initialConfig (k s n r : ℕ) (ε δ : ℚ) : MachineConfig k s where
  registers := fun i => match i.val with
    | 0 => n.bits
    | 1 => r.bits
    | 2 => ε.num.natAbs.bits
    | 3 => ε.den.bits
    | 4 => δ.num.natAbs.bits
    | 5 => δ.den.bits
    | _ => []
  control := 0

def machineStep {k s n : ℕ} (P : Program k s) (O : IndependenceOracle n)
    (randomBit : Bool) (c : MachineConfig k s) : MachineConfig k s :=
  if c.output.isSome then c else
  match P c.control with
  | .push i b next =>
    { c with
      registers := Function.update c.registers i (b :: c.registers i)
      control := next
      bitOperations := c.bitOperations + 1 }
  | .pop i empty zero one =>
    match c.registers i with
    | [] => { c with
      control := empty
      bitOperations := c.bitOperations + 1 }
    | b :: l =>
      { c with
      registers := Function.update c.registers i l
      control := if b then one else zero
      bitOperations := c.bitOperations + 1 }
  | .coin zero one =>
    { c with
      control := if randomBit then one else zero
      bitOperations := c.bitOperations + 1 }
  | .query which i no yes =>
    if (c.registers i).length = n then
      { c with
      control := if O which (fun j => (c.registers i)[j.val]?.getD false)
          then yes else no
      oracleCalls := c.oracleCalls + 1
      bitOperations := c.bitOperations + (c.registers i).length + n + 1 }
    else
      { c with
      output := some 0
      bitOperations := c.bitOperations + (c.registers i).length + n + 1 }
  | .halt =>
    { c with
      output := some ((binaryValue (c.registers ⟨6, by omega⟩) : ℚ) /
        (binaryValue (c.registers ⟨7, by omega⟩) : ℚ))
      bitOperations := c.bitOperations + (c.registers ⟨6, by omega⟩).length +
        (c.registers ⟨7, by omega⟩).length + 1 }

def execution {k s n : ℕ} (P : Program k s) (O : IndependenceOracle n)
    (c : MachineConfig k s) (bits : ℕ → Bool) : ℕ → MachineConfig k s
  | 0 => c
  | t + 1 => machineStep P O (bits t) (execution P O c bits t)

def finiteBits {B : ℕ} (bits : Fin B → Bool) (t : ℕ) : Bool :=
  if h : t < B then bits ⟨t, h⟩ else false

def relativeAccuracy (ε : ℚ) (Z : ℕ) (z : ℚ) : Prop :=
  (1-ε)*(Z:ℚ)≤z ∧ z≤(1+ε)*(Z:ℚ)

def resourceBound (C d n r : ℕ) (ε δ : ℚ) : ℕ :=
  C * (1 + n + inputLength n r ε δ + ⌈ε⁻¹⌉₊ + Nat.clog 2 ⌈δ⁻¹⌉₊) ^ d

def MainTheorem : Prop :=
  ∃ (k s : ℕ) (P : Program k s) (C d : ℕ), 0 < C ∧
    ∀ (n r : ℕ) (M₁ M₂ : Matroid (Fin n)) (O : IndependenceOracle n)
      (ε δ : ℚ),
      M₁.E = Set.univ → M₂.E = Set.univ →
      M₁.eRank = (r : ℕ∞) → M₂.eRank = (r : ℕ∞) →
      ExactOracles M₁ M₂ O → 0 < ε → ε < 1 → 0 < δ → δ < 1 →
      let B := resourceBound C d n r ε δ
      let Z := commonBaseCount M₁ M₂
      (∀ bits : ℕ → Bool,
        let out := execution P O (initialConfig k s n r ε δ) bits B
        out.output.isSome ∧ out.oracleCalls ≤ B ∧ out.bitOperations ≤ B ∧
        ∀ z, out.output = some z → 0 ≤ z ∧ (Z = 0 → z = 0)) ∧
      (1 - δ) * (2 : ℚ) ^ B ≤
        (Nat.card {bits : Fin B → Bool //
          ∃ z, (execution P O (initialConfig k s n r ε δ) (finiteBits bits) B).output
            = some z ∧ relativeAccuracy ε Z z} : ℚ)

end CommonBasesFPRAS

theorem common_bases_fpras : CommonBasesFPRAS.MainTheorem := by
  sorry

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/CommonBasesFPRAS.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.common_bases_fpras` must keep exactly the statement shown above: same names,
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
