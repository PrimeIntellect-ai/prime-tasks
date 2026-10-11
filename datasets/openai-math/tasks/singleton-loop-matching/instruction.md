# openai/math challenge `SingletonLoopMatching` (family 113)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 113 of the release, *Approximate counting and the perfect-matching entropy conjecture*
(Theoretical computer science). The family as a whole: Gives a fully polynomial randomized approximation scheme for counting perfect matchings in arbitrary finite simple graphs, with exact detection of zero counts. Also proves the perfect-matching entropy conjecture of Anari, Oveis Gharan, and Vinzant, bounding the maximum entropy of a matching law at every feasible edge-marginal vector in a loopless labelled multigraph, including boundary points.

The challenge is `SingletonLoopMatching`, also at `/opt/openai-math/challenges/SingletonLoopMatching.lean`:

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


def encodeNat (n : ℕ) : List Bool :=
  List.replicate n.bits.length false ++ true :: n.bits

def encodeRecord (r : Record) : List Bool :=
  encodeNat r.left ++ encodeNat r.right ++ encodeNat r.multiplicity

def encodeInput (G : Input) : List Bool :=
  encodeNat G.n ++ encodeNat G.records.length ++ G.records.flatMap encodeRecord

end BinaryMatching

open scoped BigOperators

namespace LoopMatching

structure LoopRecord where
  vertex : ℕ
  multiplicity : ℕ
  deriving DecidableEq

structure Input where
  ordinary : BinaryMatching.Input
  loops : List LoopRecord
  valid : ∀ e ∈ loops, e.vertex < ordinary.n
  unique : (loops.map LoopRecord.vertex).Nodup

abbrev Input.n (G : Input) : ℕ := G.ordinary.n

def loopMultiplicity (G : Input) (v : Fin G.n) : ℕ :=
  match G.loops.find? (fun r => r.vertex == v.val) with
  | none => 0
  | some r => r.multiplicity

def IsPartialMatching (n : ℕ) (M : Finset (BinaryMatching.Pair n)) : Prop :=
  ∀ v : Fin n, ∀ e ∈ M, ∀ f ∈ M,
    (BinaryMatching.completeGraph n).Incident v e →
    (BinaryMatching.completeGraph n).Incident v f → e = f

abbrev PartialMatching (n : ℕ) :=
  { M : Finset (BinaryMatching.Pair n) // IsPartialMatching n M }

noncomputable instance partialMatchingFintype (n : ℕ) : Fintype (PartialMatching n) :=
  Fintype.ofFinite _

noncomputable def loopVertices {n : ℕ} (M : PartialMatching n) : Finset (Fin n) := by
  classical
  exact Finset.univ.filter (fun v =>
    ∀ e ∈ M.val, ¬ (BinaryMatching.completeGraph n).Incident v e)

noncomputable def weight (G : Input) (M : PartialMatching G.n) : ℕ :=
  (∏ e ∈ M.val, BinaryMatching.multiplicity G.ordinary e) *
    ∏ v ∈ loopVertices M, loopMultiplicity G v

noncomputable def count (G : Input) : ℕ := ∑ M : PartialMatching G.n, weight G M


def encodeLoopRecord (r : LoopRecord) : List Bool :=
  BinaryMatching.encodeNat r.vertex ++ BinaryMatching.encodeNat r.multiplicity

def encodeInput (G : Input) : List Bool :=
  BinaryMatching.encodeInput G.ordinary ++
    BinaryMatching.encodeNat G.loops.length ++ G.loops.flatMap encodeLoopRecord

def encodeOutput (a : ℕ × ℕ) : List Bool :=
  BinaryMatching.encodeNat a.1 ++ BinaryMatching.encodeNat a.2


def FullEndpoint : Prop :=
  ∃ A : Input → ℕ × ℕ,
    ∃ machine : Turing.TM2ComputableInPolyTime encodeInput encodeOutput A,
      (∀ k, Finite (machine.tm.Γ k)) ∧
      (∃ P : Polynomial ℕ, ∀ G,
        (encodeOutput (A G)).length ≤ P.eval (encodeInput G).length) ∧
      ∀ G, 0 < (A G).2 ∧
        (A G).1 ≤ (A G).2 * count G ∧
        (A G).2 * count G ≤ 2 ^ (18 * G.n) * (A G).1 ∧
        ((A G).1 = 0 ↔ count G = 0)

end LoopMatching

namespace LoopMatching

/-- A finite-alphabet polynomial-time rational approximation for singleton-loop matchings. -/
theorem fullEndpoint : FullEndpoint := by
  sorry

end LoopMatching

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SingletonLoopMatching.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.LoopMatching.fullEndpoint` must keep exactly the statement shown above: same names,
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
