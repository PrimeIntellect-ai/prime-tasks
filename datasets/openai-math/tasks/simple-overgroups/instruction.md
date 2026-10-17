# openai/math challenge `SimpleOvergroups` (family 250)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 250 of the release, *The Boone–Higman conjecture and higher finiteness*
(Group theory). The family as a whole: A finitely generated group has decidable word problem exactly when it embeds in a finitely presented simple group, proving the Boone–Higman conjecture. The target can have type $F_\infty$: a classifying space with finitely many cells in each dimension. A single group of type $F_\infty$ can also contain every finitely presented group.

The challenge is `SimpleOvergroups`, also at `/opt/openai-math/challenges/SimpleOvergroups.lean`:

```lean
import Mathlib

namespace OAI

namespace SimpleFInftyOvergroups
universe u

def evalWord {G : Type u} [Group G] {n : ℕ} (g : Fin n → G)
    (w : List (Fin n × Bool)) : G :=
  (w.map fun x => if x.2 then g x.1 else (g x.1)⁻¹).prod

def HasDecidableWordProblem (G : Type u) [Group G] : Prop :=
  ∃ (n : ℕ) (g : Fin n → G), Subgroup.closure (Set.range g) = ⊤ ∧
    ComputablePred (fun w : List (Fin n × Bool) => evalWord g w = 1)

def HasTypeFInfty (H : Type u) [Group H] : Prop :=
  ∃ (X : Type u) (topology : TopologicalSpace X),
    letI : TopologicalSpace X := topology
    ∃ (cw : Topology.CWComplex (Set.univ : Set X)),
      letI : Topology.CWComplex (Set.univ : Set X) := cw
      T2Space X ∧ ConnectedSpace X ∧
      Topology.CWComplex.FiniteType (Set.univ : Set X) ∧
      ∃ (x : X), Nonempty (H ≃* FundamentalGroup X x) ∧
        ∃ (E : Type u) (coverTopology : TopologicalSpace E),
          letI : TopologicalSpace E := coverTopology
          ∃ (p : E → X), IsCoveringMap p ∧ Function.Surjective p ∧ ContractibleSpace E

theorem main (G : Type u) [Group G] [Group.FG G]
    (hG : HasDecidableWordProblem G) :
    ∃ (H : Type u) (_ : Group H), Nontrivial H ∧ IsSimpleGroup H ∧
      HasTypeFInfty H ∧ ∃ f : G →* H, Function.Injective f := by
  sorry

end SimpleFInftyOvergroups

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SimpleOvergroups.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SimpleFInftyOvergroups.main` must keep exactly the statement shown above: same names,
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
