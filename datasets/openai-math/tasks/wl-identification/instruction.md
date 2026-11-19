# openai/math challenge `WLIdentification` (family 133)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 133 of the release, *The complexity of Weisfeiler–Leman refinement*
(Theoretical computer science). The family as a whole: Proves unconditional $n^{\Omega(k)}$ deterministic time lower bounds for joint and separate $k$-dimensional Weisfeiler–Leman equivalence, for sufficiently large fixed $k$ in the specified sequential adjacency-matrix models. With dimension as input, joint equivalence is EXPTIME-complete even on subcubic graphs; deciding whether refinement identifies a graph is also EXPTIME-complete.

The challenge is `WLIdentification`, also at `/opt/openai-math/challenges/WLIdentification.lean`:

```lean
import Mathlib

namespace OAI

namespace WLIdentification

structure Graph where
  order : ℕ
  edge : Fin order → Fin order → Bool
  symmetric : ∀ u v, edge u v = edge v u
  loopless : ∀ u, edge u u = false

def Isomorphic (G H : Graph) : Prop :=
  ∃ e : Fin G.order ≃ Fin H.order, ∀ u v, G.edge u v = H.edge (e u) (e v)

/-- Colors retain their full history, and hence are shared between graphs. -/
def NeighborColor : ℕ → Type
  | 0 => Unit
  | s + 1 => NeighborColor s × Multiset (NeighborColor s)

def neighborColor (G : Graph) : (s : ℕ) → Fin G.order → NeighborColor s
  | 0, _ => ()
  | s + 1, v => (neighborColor G s v,
      (Finset.univ.filter (fun w => G.edge v w = true)).val.map (neighborColor G s))

def neighborHistogram (G : Graph) (s : ℕ) : Multiset (NeighborColor s) :=
  Finset.univ.val.map (neighborColor G s)

def TupleColor (k : ℕ) : ℕ → Type
  | 0 => (Fin k → Fin k → Bool) × (Fin k → Fin k → Bool)
  | s + 1 => TupleColor k s × Multiset (Fin k → TupleColor k s)

/-- Joint update: one multiset of whole replacement vectors, not independent marginals. -/
def tupleColor (G : Graph) (k : ℕ) : (s : ℕ) → (Fin k → Fin G.order) → TupleColor k s
  | 0, v => (fun i j => decide (v i = v j), fun i j => G.edge (v i) (v j))
  | s + 1, v => (tupleColor G k s v,
      Finset.univ.val.map (fun z => fun i => tupleColor G k s (Function.update v i z)))

def tupleHistogram (G : Graph) (k s : ℕ) : Multiset (TupleColor k s) :=
  Finset.univ.val.map (tupleColor G k s)

def Equivalent (k : ℕ) (G H : Graph) : Prop :=
  if k = 1 then ∀ s, neighborHistogram G s = neighborHistogram H s
  else ∀ s, tupleHistogram G k s = tupleHistogram H k s

/-- There is no restriction to mates from a graph construction or to a selected order. -/
def Identifies (k : ℕ) (G : Graph) : Prop :=
  ∀ H : Graph, Equivalent k G H → Isomorphic G H

/-- The infimum of the positive identifying dimensions; this set is nonempty for finite G. -/
noncomputable def WLdim (G : Graph) : ℕ :=
  sInf {k : ℕ | 0 < k ∧ Identifies k G}

abbrev Word := List Bool
abbrev BinaryLanguage := Set Word

def binaryValue (bits : Word) : ℕ :=
  bits.foldl (fun z b => 2 * z + if b then 1 else 0) 0

def matrixWord (G : Graph) : Word :=
  (List.ofFn (fun i : Fin G.order => List.ofFn (G.edge i))).flatten

/-- Unary order header, row-major binary matrix, then most-significant-first binary k. -/
def inputWord (G : Graph) (bits : Word) : Word :=
  List.replicate G.order true ++ [false] ++ matrixWord G ++ bits

/-- A malformed word is rejected: membership requires a valid nonempty simple matrix and k>0. -/
def dimensionLanguage : BinaryLanguage :=
  {w | ∃ (G : Graph) (bits : Word),
    0 < G.order ∧ (∃ tail, bits = true :: tail) ∧ 0 < binaryValue bits ∧
    w = inputWord G bits ∧ WLdim G ≤ binaryValue bits}

/- The deterministic local machine model is explicit; no oracle or arbitrary
   state-transition on whole inputs is included. Both alphabets are fixed finite
   types for each machine. Extra symbols and states allow arbitrary finite tables. -/
inductive Move where
  | left | stay | right
  deriving DecidableEq

def Move.displacement : Move → ℤ
  | .left => -1
  | .stay => 0
  | .right => 1

structure Machine where
  extraSymbols : ℕ
  extraStates : ℕ
  transition : Fin (extraStates + 3) → Fin (extraSymbols + 3) →
    Fin (extraStates + 3) × Fin (extraSymbols + 3) × Move

structure Configuration (M : Machine) where
  state : Fin (M.extraStates + 3)
  head : ℤ
  tape : ℤ → Fin (M.extraSymbols + 3)

def inputSymbol (M : Machine) (b : Bool) : Fin (M.extraSymbols + 3) :=
  if b then 2 else 1

def initial (M : Machine) (w : Word) : Configuration M where
  state := 0
  head := 0
  tape z := if 0 ≤ z then (w[z.toNat]?).elim 0 (inputSymbol M) else 0

def Halted {M : Machine} (c : Configuration M) : Prop :=
  c.state = 1 ∨ c.state = 2

/-- One read/write/head-movement transition. A halted configuration is frozen. -/
def step (M : Machine) (c : Configuration M) : Configuration M :=
  if c.state = 1 ∨ c.state = 2 then c else
    let t := M.transition c.state (c.tape c.head)
    { state := t.1, head := c.head + t.2.2.displacement,
      tape := Function.update c.tape c.head t.2.1 }

def run (M : Machine) (w : Word) (t : ℕ) : Configuration M :=
  (step M)^[t] (initial M w)

/-- Output is the binary word beginning at origin and ending at its first blank. -/
def Output {M : Machine} (c : Configuration M) (w : Word) : Prop :=
  (∀ i : Fin w.length, c.tape (i.val : ℤ) = inputSymbol M w[i]) ∧
    c.tape (w.length : ℤ) = 0

/-- Uniform genuine executions on every bit word, including malformed graph words. -/
def DecidesWithin (M : Machine) (L : BinaryLanguage) (bound : ℕ → ℕ) : Prop :=
  ∀ w, ∃ t ≤ bound w.length, Halted (run M w t) ∧ ((run M w t).state = 1 ↔ w ∈ L)

def InEXPTIME (L : BinaryLanguage) : Prop :=
  ∃ (M : Machine) (C d : ℕ),
    DecidesWithin M L (fun n => 2 ^ (C * (n + 1) ^ d))

def ComputesWithin (M : Machine) (f : Word → Word) (bound : ℕ → ℕ) : Prop :=
  ∀ w, ∃ t ≤ bound w.length, (run M w t).state = 1 ∧ Output (run M w t) (f w)

def PolytimeManyOne (L S : BinaryLanguage) : Prop :=
  ∃ (f : Word → Word) (M : Machine) (C d : ℕ),
    ComputesWithin M f (fun n => C * (n + 1) ^ d) ∧ ∀ w, w ∈ L ↔ f w ∈ S

def EXPTIMEComplete (S : BinaryLanguage) : Prop :=
  InEXPTIME S ∧ ∀ L : BinaryLanguage, InEXPTIME L → PolytimeManyOne L S

theorem main : EXPTIMEComplete dimensionLanguage :=
  by
    sorry

end WLIdentification

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/WLIdentification.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.WLIdentification.main` must keep exactly the statement shown above: same names,
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
