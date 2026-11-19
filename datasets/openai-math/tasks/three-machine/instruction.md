# openai/math challenge `ThreeMachine` (family 124)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 124 of the release, *Polynomial-time scheduling on three identical machines*
(Theoretical computer science). The family as a whole: Resolves the three-processor unit-job scheduling problem of Garey and Johnson: a deterministic polynomial-time algorithm minimizes makespan for nonpreemptive unit-length jobs with arbitrary precedence constraints on three identical parallel machines. For an explicitly given precedence graph, it decides deadline feasibility exactly and constructs a feasible schedule.

The challenge is `ThreeMachine`, also at `/opt/openai-math/challenges/ThreeMachine.lean`:

```lean
import Mathlib

namespace OAI

namespace ThreeMachine

structure Instance (n : ℕ) where
  edges : List (Fin n × Fin n)

def Instance.edge {n : ℕ} (G : Instance n) (u v : Fin n) : Prop :=
  (u, v) ∈ G.edges

def Instance.acyclic {n : ℕ} (G : Instance n) : Prop :=
  ∀ v, ¬Relation.TransGen G.edge v v

def Feasible {n : ℕ} (G : Instance n) (T : ℕ) (τ : Fin n → ℕ) : Prop :=
  (∀ v, 1 ≤ τ v ∧ τ v ≤ T) ∧
  (∀ t, ((Finset.univ : Finset (Fin n)).filter (fun v => τ v = t)).card ≤ 3) ∧
  ∀ u v, G.edge u v → τ u < τ v

def encodeNat (n : ℕ) : List Bool :=
  let b := Computability.encodeNat n
  List.replicate b.length true ++ false :: b

def encodeList {α : Type} (f : α → List Bool) (xs : List α) : List Bool :=
  encodeNat xs.length ++ xs.flatMap f

def encodeInput {n : ℕ} (G : Instance n) (deadline : Option ℕ) : List Bool :=
  (match deadline with
    | none => [false]
    | some T => true :: encodeNat T) ++
  encodeList encodeNat ((List.range n).map (· + 1)) ++
  encodeList (fun (e : Fin n × Fin n) => encodeNat (e.1.val + 1) ++
    encodeNat (e.2.val + 1)) G.edges

def encodeAnswer : Option (List ℕ) → List Bool
  | none => [false]
  | some slots => true :: encodeList encodeNat slots

def slots {n : ℕ} (τ : Fin n → ℕ) : List ℕ := List.ofFn τ

def CorrectOutput {n : ℕ} (G : Instance n) (deadline : Option ℕ)
    (out : List Bool) : Prop :=
  match deadline with
  | none => ∃ T τ, Feasible G T τ ∧
      (∀ T' τ', Feasible G T' τ' → T ≤ T') ∧
      out = encodeAnswer (some (slots τ))
  | some T =>
      (out = encodeAnswer none ∧ ¬∃ τ, Feasible G T τ) ∨
      ∃ τ, Feasible G T τ ∧ out = encodeAnswer (some (slots τ))

structure Machine (k q g : ℕ) where
  transition : Fin (q + 1) → (Fin (k + 1) → Fin (g + 3)) →
    Option (Fin (q + 1) × (Fin (k + 1) → Fin (g + 3) × Option Turing.Dir))

structure Configuration (k q g : ℕ) where
  state : Fin (q + 1)
  tapes : Fin (k + 1) → Turing.Tape (Fin (g + 3))

def bitSymbol {g : ℕ} (b : Bool) : Fin (g + 3) :=
  if b then ⟨2, by omega⟩ else ⟨1, by omega⟩

def Machine.step {k q g : ℕ} (M : Machine k q g)
    (c : Configuration k q g) : Option (Configuration k q g) := do
  let (state, action) ← M.transition c.state (fun i => (c.tapes i).head)
  return { state := state, tapes := fun i =>
    let tape := (c.tapes i).write (action i).1
    match (action i).2 with
    | none => tape
    | some d => tape.move d }

def Machine.initial {k q g : ℕ} (_M : Machine k q g)
    (input : List Bool) : Configuration k q g :=
  { state := 0, tapes := fun i =>
      Turing.Tape.mk₁ (if i = 0 then input.map bitSymbol else []) }

def Machine.run {k q g : ℕ} (M : Machine k q g) (input : List Bool)
    (t : ℕ) : Configuration k q g :=
  (fun c => (M.step c).getD c)^[t] (M.initial input)

def Machine.Produces {k q g : ℕ} (M : Machine k q g)
    (input out : List Bool) (timeBound : ℕ) : Prop :=
  ∃ t ≤ timeBound, M.step (M.run input t) = none ∧
    ((M.run input t).tapes 0).right₀ = Turing.ListBlank.mk (out.map bitSymbol)

def ReleaseTheorem : Prop :=
  ∃ (k q g : ℕ) (M : Machine k q g) (C : ℕ), 0 < C ∧
    ∀ n (G : Instance n), 1 ≤ n → G.acyclic →
      ∀ deadline : Option ℕ,
        (∀ T ∈ deadline, 1 ≤ T ∧ T ≤ n) →
        ∃ out, CorrectOutput G deadline out ∧
          M.Produces (encodeInput G deadline) out
            (C * ((encodeInput G deadline).length + 2) ^ 150020)

theorem main_theorem : ReleaseTheorem := by
  sorry

end ThreeMachine

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/ThreeMachine.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.ThreeMachine.main_theorem` must keep exactly the statement shown above: same names,
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
