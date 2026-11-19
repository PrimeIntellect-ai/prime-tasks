# openai/math challenge `PeriodicGroup` (family 247)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 247 of the release, *An infinite finitely presented residually finite $2$-group*
(Group theory). The family as a whole: Constructs an infinite finitely presented residually finite group whose elements all have finite $2$-power order, answering the finitely presented Burnside problem negatively even in this class. The construction also yields an infinite-dimensional finitely presented nil associative $\mathbb F_2$-algebra and a finitely presented infinite-dimensional algebraic unitization, giving negative answers to the corresponding nilpotence and Kurosh finiteness questions.

The challenge is `PeriodicGroup`, also at `/opt/openai-math/challenges/PeriodicGroup.lean`:

```lean
import Mathlib

namespace OAI

universe u

namespace SourceBurnside

structure Root (n : ℕ) where
  row : Fin n
  col : Fin n
  ne : row ≠ col
  deriving DecidableEq

abbrev Generator (n : ℕ) (R : Type u) := Root n × R

def bracket {G : Type u} [Group G] (x y : G) : G := x * y * x⁻¹ * y⁻¹

def letter {n : ℕ} {R : Type u} (p : Root n) (a : R) :
    FreeGroup (Generator n R) := FreeGroup.of (p, a)

inductive SteinbergRel (n : ℕ) (R : Type u) [Ring R] :
    FreeGroup (Generator n R) → Prop
  | add (p : Root n) (a b : R) :
      SteinbergRel n R (letter p (a + b) * (letter p a * letter p b)⁻¹)
  | commute (p q : Root n) (h₁ : p.col ≠ q.row) (h₂ : p.row ≠ q.col) (a b : R) :
      SteinbergRel n R (bracket (letter p a) (letter q b))
  | mul (i j k : Fin n) (hij : i ≠ j) (hjk : j ≠ k) (hik : i ≠ k) (a b : R) :
      SteinbergRel n R
        (bracket (letter ⟨i, j, hij⟩ a) (letter ⟨j, k, hjk⟩ b) *
          (letter ⟨i, k, hik⟩ (a * b))⁻¹)

def Steinberg (n : ℕ) (R : Type u) [Ring R] :=
  PresentedGroup {r | SteinbergRel n R r}
  deriving Group

def Periodic (G : Type u) [Group G] : Prop := ∀ g : G, ∃ m : ℕ, 0 < m ∧ g ^ m = 1

def MainStatement : Prop :=
  ∃ (R : Type) (_ : Ring R) (_ : Algebra (ZMod 2) R),
    Infinite (Steinberg 12 R) ∧ Group.IsFinitelyPresented (Steinberg 12 R) ∧
      Periodic (Steinberg 12 R)

def BurnsideStatement : Prop :=
  ∃ (G : Type) (_ : Group G), Infinite G ∧ Group.IsFinitelyPresented G ∧ Periodic G

end SourceBurnside

namespace SourceBurnside

theorem thm_main : MainStatement ∧ BurnsideStatement := by
  sorry

end SourceBurnside

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/PeriodicGroup.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SourceBurnside.thm_main` must keep exactly the statement shown above: same names,
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
