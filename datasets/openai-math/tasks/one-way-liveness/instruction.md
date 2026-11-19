# openai/math challenge `OneWayLiveness` (family 129)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 129 of the release, *Exponential state costs for two-way automata*
(Theoretical computer science). The family as a whole: Proves exponential lower bounds both for complementing two-way nondeterministic finite automata and for simulating one-way nondeterministic automata by two-way deterministic ones. The latter resolves the Sakoda–Sipser state-succinctness conjecture over growing finite alphabets; both results rule out polynomial state bounds independent of alphabet size.

The challenge is `OneWayLiveness`, also at `/opt/openai-math/challenges/OneWayLiveness.lean`:

```lean
import Mathlib

namespace OAI

namespace OneWayLiveness

@[ext] structure BRel (H : Type*) where
  holds : H → H → Prop

namespace BRel
variable {H : Type*}
instance : One (BRel H) := ⟨⟨Eq⟩⟩
instance : Mul (BRel H) := ⟨fun a b => ⟨fun x z => ∃ y, a.holds x y ∧ b.holds y z⟩⟩
instance : Monoid (BRel H) where
  mul_assoc a b c := by
    ext x z
    change (∃ y, (∃ w, a.holds x w ∧ b.holds w y) ∧ c.holds y z) ↔
      ∃ w, a.holds x w ∧ ∃ y, b.holds w y ∧ c.holds y z
    aesop
  one_mul a := by ext x z; change (∃ y, x = y ∧ a.holds y z) ↔ a.holds x z; simp
  mul_one a := by ext x z; change (∃ y, a.holds x y ∧ y = z) ↔ a.holds x z; simp

/-- Nonemptiness is the existence of a path through the word's ordered product. -/
def live (w : List (BRel H)) : Prop := ∃ x y, w.prod.holds x y
end BRel

abbrev Alphabet (h : ℕ) := BRel (Fin h)
def OWL (h : ℕ) : Set (List (Alphabet h)) := {w | BRel.live w}

inductive Symbol (Alpha : Type*) where
  | left : Symbol Alpha
  | letter : Alpha → Symbol Alpha
  | right : Symbol Alpha

inductive Move where
  | left | stay | right
  deriving DecidableEq

def Move.Rel : Move → ℕ → ℕ → Prop
  | .left, i, j => j + 1 = i
  | .stay, i, j => j = i
  | .right, i, j => j = i + 1

/-- The finite word including both endmarkers. -/
def scanned {Alpha : Type*} (w : List Alpha) (i : Fin (w.length + 2)) : Symbol Alpha :=
  if h0 : i.val = 0 then .left
  else if hi : i.val < w.length + 1 then .letter (w[i.val - 1]'(by omega))
  else .right

abbrev Configuration {Alpha : Type*} (w : List Alpha) (n : ℕ) := Fin (w.length + 2) × Fin n

structure DMachine (Alpha : Type*) (s : ℕ) where
  initial : Fin s
  accepting : Set (Fin s)
  transition : Fin s → Symbol Alpha → Option (Fin s × Move)
  left_boundary : ∀ q q', transition q .left ≠ some (q', .left)
  right_boundary : ∀ q q', transition q .right ≠ some (q', .right)

structure NMachine (Alpha : Type*) (n : ℕ) where
  initial : Fin n
  accepting : Set (Fin n)
  transition : Fin n → Symbol Alpha → Set (Fin n × Move)
  left_boundary : ∀ q q', (q', .left) ∉ transition q .left
  right_boundary : ∀ q q', (q', .right) ∉ transition q .right

def DMachine.Step {Alpha : Type*} {s : ℕ} (M : DMachine Alpha s) (w : List Alpha)
    (c c' : Configuration w s) : Prop :=
  ∃ d, M.transition c.2 (scanned w c.1) = some (c'.2, d) ∧ d.Rel c.1.val c'.1.val

def NMachine.Step {Alpha : Type*} {n : ℕ} (M : NMachine Alpha n) (w : List Alpha)
    (c c' : Configuration w n) : Prop :=
  ∃ d, (c'.2, d) ∈ M.transition c.2 (scanned w c.1) ∧ d.Rel c.1.val c'.1.val

/-- The positive convention explicitly excludes a length-zero computation. -/
def FiniteRun {C : Type*} (positive : Bool) (step : C → C → Prop) (c c' : C) : Prop :=
  if positive then Relation.TransGen step c c' else Relation.ReflTransGen step c c'

def DMachine.Accepts {Alpha : Type*} {s : ℕ} (M : DMachine Alpha s)
    (positive : Bool) (w : List Alpha) : Prop :=
  ∃ c, FiniteRun positive (M.Step w) (⟨0, by omega⟩, M.initial) c ∧ c.2 ∈ M.accepting

def NMachine.Accepts {Alpha : Type*} {n : ℕ} (M : NMachine Alpha n)
    (positive : Bool) (w : List Alpha) : Prop :=
  ∃ c, FiniteRun positive (M.Step w) (⟨0, by omega⟩, M.initial) c ∧ c.2 ∈ M.accepting

def NMachine.NoLeft {Alpha : Type*} {n : ℕ} (M : NMachine Alpha n) : Prop :=
  ∀ q a q', (q', Move.left) ∉ M.transition q a

def NMachine.Recognizes {Alpha : Type*} {n : ℕ} (M : NMachine Alpha n)
    (positive : Bool) (L : Set (List Alpha)) : Prop := ∀ w, M.Accepts positive w ↔ w ∈ L

def DMachine.Recognizes {Alpha : Type*} {s : ℕ} (M : DMachine Alpha s)
    (positive : Bool) (L : Set (List Alpha)) : Prop := ∀ w, M.Accepts positive w ↔ w ∈ L

theorem main_theorem (h : ℕ) (hh : 2 ≤ h) :
    (∃ N : NMachine (Alphabet h) (h + 3), N.NoLeft ∧
      ∀ positive : Bool, N.Recognizes positive (OWL h)) ∧
    (∀ (positive : Bool) (s : ℕ) (D : DMachine (Alphabet h) s),
      D.Recognizes positive (OWL h) →
      2 ^ ((h - 2) / 31) ≤ 4 * (s + if positive then 2 else 1) ^ 2) := by
  sorry

end OneWayLiveness

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/OneWayLiveness.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.OneWayLiveness.main_theorem` must keep exactly the statement shown above: same names,
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
