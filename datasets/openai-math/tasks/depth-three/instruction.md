# openai/math challenge `DepthThree` (family 112)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 112 of the release, *Beyond the square-root exponent for depth-three circuits*
(Theoretical computer science). The family as a whole: Constructs a single language in deterministic polynomial time whose $n$-bit membership function requires $2^{\omega(\sqrt n)}$ total gates in unbounded-fan-in OR–AND–OR circuits, at every sufficiently large input length. This crosses the square-root-exponent threshold for explicit depth-three Boolean circuit lower bounds.

The challenge is `DepthThree`, also at `/opt/openai-math/challenges/DepthThree.lean`:

```lean
import Mathlib

namespace OAI

namespace DepthThreeLowerBound

universe uV uS uK uGamma uQ

abbrev Cube (V : Type uV) := V → Bool
abbrev Literal (V : Type uV) := V × Bool

variable {V : Type uV}

namespace Literal

def eval (l : Literal V) (x : Cube V) : Bool := decide (x l.1 = l.2)

end Literal

abbrev GateInput (V : Type uV) := Sum (Literal V) Bool
abbrev RawClause (V : Type uV) := List (GateInput V)

namespace GateInput

def eval : GateInput V → Cube V → Bool
  | .inl l, x => l.eval x
  | .inr b, _ => b

end GateInput

namespace RawClause

noncomputable def eval (C : RawClause V) (x : Cube V) : Bool := by
  classical
  exact decide (∃ l ∈ C, l.eval x = true)

end RawClause

structure Circuit3 (V : Type uV) where
  bottomCount : ℕ
  middleCount : ℕ
  bottom : Fin bottomCount → RawClause V
  middle : Fin middleCount → Finset (Fin bottomCount)
  top : Finset (Fin middleCount)

namespace Circuit3

def gateCount (C : Circuit3 V) : ℕ := C.bottomCount + C.middleCount + 1

noncomputable def middleEval (C : Circuit3 V) (j : Fin C.middleCount)
    (x : Cube V) : Bool := by
  classical
  exact decide (∀ i ∈ C.middle j, (C.bottom i).eval x = true)

noncomputable def eval (C : Circuit3 V) (x : Cube V) : Bool := by
  classical
  exact decide (∃ j ∈ C.top, C.middleEval j x = true)

def Computes (C : Circuit3 V) (f : Cube V → Bool) : Prop := ∀ x, C.eval x = f x

end Circuit3

def runSteps {S : Type uS} (step : S → Option S) (n : ℕ) (c : Option S) : Option S :=
  (fun oc => oc.bind step)^[n] c

inductive HeadMove
  | left
  | stay
  | right

def HeadMove.apply {Γ : Type uGamma} [Inhabited Γ] : HeadMove → Turing.Tape Γ → Turing.Tape Γ
  | .left, t => t.move Turing.Dir.left
  | .stay, t => t
  | .right, t => t.move Turing.Dir.right

structure MultiTapeCfg (K : Type uK) (Γ : Type uGamma) (Q : Type uQ) [Inhabited Γ] where
  q : Q
  tapes : K → Turing.Tape Γ

abbrev MultiTapeCode (K : Type uK) (Γ : Type uGamma) (Q : Type uQ) :=
  Q → (K → Γ) → Option (Q × (K → Γ) × (K → HeadMove))

def multiTapeUpdate {K : Type uK} {Γ : Type uGamma} {Q : Type uQ} [Inhabited Γ] (c : MultiTapeCfg K Γ Q)
    (q : Q) (writes : K → Γ) (moves : K → HeadMove) : MultiTapeCfg K Γ Q :=
  ⟨q, fun k => (moves k).apply ((c.tapes k).write (writes k))⟩

def multiTapeStep {K : Type uK} {Γ : Type uGamma} {Q : Type uQ} [Inhabited Γ] (code : MultiTapeCode K Γ Q)
    (c : MultiTapeCfg K Γ Q) : Option (MultiTapeCfg K Γ Q) :=
  (code c.q (fun k => (c.tapes k).head)).map fun out =>
    multiTapeUpdate c out.1 out.2.1 out.2.2

structure FiniteMultiTapeMachine where
  K : Type
  [tapeFinite : Fintype K]
  [tapeDecidableEq : DecidableEq K]
  inputTape : K
  Γ : Type
  [alphabetInhabited : Inhabited Γ]
  [alphabetFinite : Fintype Γ]
  Q : Type
  [stateFinite : Fintype Q]
  initialState : Q
  inputSymbol : Bool → Γ
  input_injective : Function.Injective inputSymbol
  input_ne_blank : ∀ b, inputSymbol b ≠ default
  code : MultiTapeCode K Γ Q
  accept : Q → Bool

attribute [instance] FiniteMultiTapeMachine.tapeFinite
  FiniteMultiTapeMachine.tapeDecidableEq FiniteMultiTapeMachine.alphabetInhabited
  FiniteMultiTapeMachine.alphabetFinite FiniteMultiTapeMachine.stateFinite

namespace FiniteMultiTapeMachine

abbrev Cfg (M : FiniteMultiTapeMachine) := MultiTapeCfg M.K M.Γ M.Q

abbrev step (M : FiniteMultiTapeMachine) : M.Cfg → Option M.Cfg :=
  multiTapeStep M.code

def init (M : FiniteMultiTapeMachine) (input : List Bool) : M.Cfg :=
  ⟨M.initialState, fun k =>
    if k = M.inputTape then Turing.Tape.mk₁ (input.map M.inputSymbol)
    else Turing.Tape.mk₁ []⟩

end FiniteMultiTapeMachine

def MultiTapeHaltsIn (M : FiniteMultiTapeMachine) (input : List Bool)
    (output : Bool) (time : ℕ) : Prop :=
  ∃ k ≤ time, ∃ c : M.Cfg,
    runSteps M.step k (some (M.init input)) = some c ∧
    M.step c = none ∧ M.accept c.q = output

theorem exists_polynomial_time_language_depth_three_lower_bound :
    ∃ (L : List Bool → Bool) (M : FiniteMultiTapeMachine) (C a : ℕ),
      0 < C ∧ 0 < a ∧
      (∀ w : List Bool, MultiTapeHaltsIn M w (L w) (C * (w.length + 1) ^ a)) ∧
      ∀ A : ℝ, 0 < A → ∃ N : ℕ, ∀ n : ℕ, N ≤ n →
        ∀ D : Circuit3 (Fin n), D.Computes (fun x => L (List.ofFn x)) →
          (2 : ℝ) ^ (A * Real.sqrt (n : ℝ)) < (D.gateCount : ℝ) := by
  sorry

end DepthThreeLowerBound

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DepthThree.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.DepthThreeLowerBound.exists_polynomial_time_language_depth_three_lower_bound` must keep exactly the statement shown above: same names,
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
