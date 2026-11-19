# openai/math challenge `DirectedFeedback` (family 102)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 102 of the release, *The Unique Games Conjecture and optimal approximation thresholds*
(Theoretical computer science). The family as a whole: Proves Khot's Unique Games Conjecture. Independent direct reductions also establish NP-hardness, on unweighted graphs, of approximation beyond the Goemans–Williamson ratio for Max-Cut, below factor two for Vertex Cover, and within any fixed constant factor for Min-UnCut and directed feedback vertex set. These direct proofs use established PCP and Label Cover hardness results.

The challenge is `DirectedFeedback`, also at `/opt/openai-math/challenges/DirectedFeedback.lean`:

```lean
import Mathlib

namespace OAI

namespace DirectedFeedback

/-- Unary self-delimiting natural numbers. Outputs are explicit, not succinct. -/
def natBits (n : ℕ) : List Bool := List.replicate n true ++ [false]

/-- The explicit framing used for an input and its NP certificate. -/
def pairBits (p : List Bool × List Bool) : List Bool :=
  natBits p.1.length ++ p.1 ++ p.2

/-- Finitely many stacks and control states are already part of `FinTM2`.
This additionally excludes infinite stack alphabets. -/
def FiniteAlphabet (M : Turing.FinTM2) : Prop := ∀ k, Finite (M.Γ k)

/-- Polynomially bounded certificates checked by an actual deterministic
finite-alphabet machine, on the explicitly encoded input/certificate pair. -/
structure NPVerifier where
  witnessBound : Polynomial ℕ
  verify : (List Bool × List Bool) → Bool
  computation : Turing.TM2ComputableInPolyTime pairBits (fun b : Bool => [b]) verify
  finiteAlphabet : FiniteAlphabet computation.tm

def NPVerifier.Accepts (V : NPVerifier) (input : List Bool) : Prop :=
  ∃ witness : List Bool, witness.length ≤ V.witnessBound.eval input.length ∧
    V.verify (input, witness) = true

/-- NP is defined independently of SAT or any hardness assertion. -/
def InNP (language : List Bool → Prop) : Prop :=
  ∃ V : NPVerifier, ∀ input, language input ↔ V.Accepts input

/-- Finite loopless digraph. Opposite arcs are permitted. Every arc is listed
explicitly. No symmetric closure or undirected-cycle convention is used. -/
structure Digraph where
  n : ℕ
  arcs : List (Fin n × Fin n)
  loopless : ∀ e ∈ arcs, e.1 ≠ e.2
  nodup : arcs.Nodup

namespace Digraph

/-- An actual simple directed cycle of positive length. A cyclic enumeration
of `r + 1` distinct vertices supplies every successive arc, including the
closing arc. A 2-cycle is allowed; looplessness rules out length 1. -/
def IsCycle (G : Digraph) {r : ℕ} (c : Fin (r + 1) → Fin G.n) : Prop :=
  Function.Injective c ∧ ∀ i, (c i, c (i + 1)) ∈ G.arcs

/-- A feedback set intersects EVERY actual directed cycle. -/
def Feedback (G : Digraph) (F : Finset (Fin G.n)) : Prop :=
  ∀ (r : ℕ) (c : Fin (r + 1) → Fin G.n), G.IsCycle c → ∃ i, c i ∈ F

/-- Minimum number of vertices of a feedback set. No weights or auxiliary
cost oracle appear in this definition. -/
noncomputable def dfvs (G : Digraph) : ℕ := by
  classical
  exact Nat.find (show ∃ k : ℕ, ∃ F : Finset (Fin G.n), G.Feedback F ∧ F.card = k from
    ⟨G.n, Finset.univ, by
      intro r c _
      exact ⟨0, Finset.mem_univ _⟩, by simp⟩)

/-- Full explicit vertex and arc serialization, including isolated vertices. -/
def bits (G : Digraph) : List Bool :=
  ([G.n] ++ List.range G.n ++ [G.arcs.length] ++
    G.arcs.flatMap (fun e => [e.1.val, e.2.val])).flatMap natBits

end Digraph

/-- Output includes a strictly positive integer threshold. -/
structure GapInstance where
  graph : Digraph
  k : ℕ
  k_pos : 0 < k

def GapInstance.bits (I : GapInstance) : List Bool :=
  natBits I.k ++ I.graph.bits

/-- A strict YES/NO gap reduction implemented by a finite-alphabet machine
with polynomial runtime in the raw input bit length. -/
structure GapReduction (A : ℝ) (language : List Bool → Prop) where
  construct : List Bool → GapInstance
  computation : Turing.TM2ComputableInPolyTime (id : List Bool → List Bool)
    GapInstance.bits construct
  finiteAlphabet : FiniteAlphabet computation.tm
  completeness : ∀ input, language input →
    (construct input).graph.dfvs ≤ (construct input).k
  soundness : ∀ input, ¬ language input →
    A * ((construct input).k : ℝ) < ((construct input).graph.dfvs : ℝ)

/-- Constant-factor directed feedback vertex set hardness for all NP languages. -/
def MainStatement : Prop :=
  ∀ A : ℝ, 1 ≤ A → ∀ language : List Bool → Prop,
    InNP language → Nonempty (GapReduction A language)

end DirectedFeedback

theorem DirectedFeedback.main : DirectedFeedback.MainStatement := by
  sorry

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DirectedFeedback.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.DirectedFeedback.main` must keep exactly the statement shown above: same names,
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
