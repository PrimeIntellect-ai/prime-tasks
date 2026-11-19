# openai/math challenge `BinaryMatching` (family 113)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 113 of the release, *Approximate counting and the perfect-matching entropy conjecture*
(Theoretical computer science). The family as a whole: Gives a fully polynomial randomized approximation scheme for counting perfect matchings in arbitrary finite simple graphs, with exact detection of zero counts. Also proves the perfect-matching entropy conjecture of Anari, Oveis Gharan, and Vinzant, bounding the maximum entropy of a matching law at every feasible edge-marginal vector in a loopless labelled multigraph, including boundary points.

The challenge is `BinaryMatching`, also at `/opt/openai-math/challenges/BinaryMatching.lean`:

```lean
import Mathlib

namespace OAI

universe u_1 u_2

namespace MatchingEntropy

structure LooplessGraph (V : Type u_1) (E : Type u_2) where
  left : E → V
  right : E → V
  loopless : ∀ e, left e ≠ right e

namespace LooplessGraph

variable {V : Type u_1} {E : Type u_2} [Fintype V] [Fintype E] [DecidableEq V] [DecidableEq E]
def Incident (G : LooplessGraph V E) (v : V) (e : E) : Prop :=
  G.left e=v ∨ G.right e=v
def IsPerfectMatching (G : LooplessGraph V E) (M : Finset E) : Prop :=
  ∀ v, ∃! e, e∈M ∧ G.Incident v e
abbrev Matching (G : LooplessGraph V E) := {M : Finset E // G.IsPerfectMatching M}
noncomputable instance matchingFintype (G : LooplessGraph V E) : Fintype G.Matching :=
  Fintype.ofFinite _

end LooplessGraph

end MatchingEntropy

namespace BinaryMatching

abbrev Pair (n : ℕ) := {ij : Fin n × Fin n // ij.1 < ij.2}
def completeGraph (n : ℕ) : MatchingEntropy.LooplessGraph (Fin n) (Pair n) where
  left e := e.val.1
  right e := e.val.2
  loopless e := ne_of_lt e.property

structure Record where
  left : ℕ
  right : ℕ
  multiplicity : ℕ
  deriving DecidableEq

structure Input where
  n : ℕ
  records : List Record
  valid : ∀ e∈records, e.left < e.right ∧ e.right < n
  unique : (records.map (fun e => (e.left,e.right))).Nodup

def multiplicity (G : Input) (e : Pair G.n) : ℕ :=
  match G.records.find? (fun r => r.left=e.val.1.val && r.right=e.val.2.val) with
  | none => 0
  | some r => r.multiplicity

noncomputable def count (G : Input) : ℕ :=
  ∑ M : (completeGraph G.n).Matching, ∏ e∈M.val, multiplicity G e

def encodeNat (n : ℕ) : List Bool :=
  List.replicate n.bits.length false ++ true :: n.bits

def encodeRecord (r : Record) : List Bool :=
  encodeNat r.left ++ encodeNat r.right ++ encodeNat r.multiplicity

def encodeInput (G : Input) : List Bool :=
  encodeNat G.n ++ encodeNat G.records.length ++ G.records.flatMap encodeRecord

theorem deterministic_approximate_counting :
    ∃ A : Input → ℕ,
      ∃ machine : Turing.TM2ComputableInPolyTime encodeInput Nat.bits A,
        (∀ k, Finite (machine.tm.Γ k)) ∧
        (∃ P : Polynomial ℕ, ∀ G,(A G).bits.length≤P.eval (encodeInput G).length) ∧
        ∀ G,A G≤count G ∧ count G≤2^(9*G.n)*A G ∧ (A G=0 ↔ count G=0) := by
  sorry

end BinaryMatching

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/BinaryMatching.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.BinaryMatching.deterministic_approximate_counting` must keep exactly the statement shown above: same names,
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
