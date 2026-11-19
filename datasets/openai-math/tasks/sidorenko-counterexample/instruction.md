# openai/math challenge `SidorenkoCounterexample` (family 161)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 161 of the release, *Counterexamples to Sidorenko's conjecture and the forcing conjecture*
(Combinatorics). The family as a whole: Disproves Sidorenko's conjecture with a connected bipartite pattern on $35$ vertices and $66$ edges that occurs less frequently than in a random graph of the same edge density. The same pattern disproves the forcing conjecture of Skokan and Thoma: matching its density and the edge density of a constant graphon need not force quasirandomness.

The challenge is `SidorenkoCounterexample`, also at `/opt/openai-math/challenges/SidorenkoCounterexample.lean`:

```lean
import Mathlib

namespace OAI

/-! # A finite counterexample to Sidorenko's conjecture

The pattern is the incidence graph of the 22 triples in Table 1 of the source.
Homomorphism density counts all edge-preserving maps, including noninjective maps.
-/

namespace SidorenkoCounterexample

def faces : Fin 22 → Finset (Fin 13) := ![
  {0,1,3}, {0,1,9}, {0,2,3}, {0,2,9}, {1,3,10}, {1,7,10},
  {1,7,12}, {1,9,12}, {2,3,4}, {2,4,9}, {3,4,11}, {3,10,11},
  {4,8,9}, {4,8,11}, {5,6,7}, {5,6,11}, {5,7,10}, {5,10,11},
  {6,7,12}, {6,8,11}, {6,8,12}, {8,9,12}]

abbrev PatternVertex := Fin 13 ⊕ Fin 22

def incidence : PatternVertex → PatternVertex → Prop
  | .inl point, .inr face => point ∈ faces face
  | .inr face, .inl point => point ∈ faces face
  | _, _ => False

def H : SimpleGraph PatternVertex where
  Adj := incidence
  symm.symm := by intro left right; cases left <;> cases right <;> simp [incidence]
  loopless.irrefl := by intro vertex; cases vertex <;> simp [incidence]

noncomputable def homCount {V W : Type*} (F : SimpleGraph V) (G : SimpleGraph W) : ℕ :=
  Nat.card {hom : V → W // ∀ left right, F.Adj left right → G.Adj (hom left) (hom right)}

noncomputable def homDensity {V W : Type*} (F : SimpleGraph V) (G : SimpleGraph W) : ℝ :=
  (homCount F G : ℝ) / (Nat.card W : ℝ) ^ Nat.card V

noncomputable def edgeDensity {W : Type*} (G : SimpleGraph W) : ℝ :=
  2 * (Nat.card G.edgeSet : ℝ) / (Nat.card W : ℝ) ^ 2

/-- A finite simple host with at least one edge violates Sidorenko's inequality. -/
theorem main : ∃ size : ℕ, 0 < size ∧ ∃ host : SimpleGraph (Fin size),
    (∃ left right, host.Adj left right) ∧ homDensity H host < (edgeDensity host) ^ 66 := by
  sorry

end SidorenkoCounterexample

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SidorenkoCounterexample.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SidorenkoCounterexample.main` must keep exactly the statement shown above: same names,
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
