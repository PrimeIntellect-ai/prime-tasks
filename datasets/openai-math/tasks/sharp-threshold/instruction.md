# openai/math challenge `SharpThreshold` (family 186)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 186 of the release, *The Friedgut–Kalai graph and hypergraph threshold conjectures*
(Combinatorics). The family as a whole: Proves the Friedgut–Kalai threshold-width conjectures for graphs and fixed-uniformity hypergraphs. For fixed $0<\varepsilon<1/2$, every nontrivial increasing relabeling-invariant property crosses from probability $\varepsilon$ to $1-\varepsilon$ within width $O((\log n)^{-2})$ for graphs and $O_r((\log n)^{-r/(r-1)})$ for $r$-uniform hypergraphs, $r\ge3$. The hypergraph influence bound also applies to nonmonotone properties.

The challenge is `SharpThreshold`, also at `/opt/openai-math/challenges/SharpThreshold.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section

namespace Problem313

abbrev GraphEdge (n : ℕ) := {e : Finset (Fin n) // e.card = 2}

abbrev GraphConfig (n : ℕ) := GraphEdge n → Bool

def permEdge {n : ℕ} (π : Equiv.Perm (Fin n)) (e : GraphEdge n) : GraphEdge n :=
  ⟨e.1.map π.toEmbedding, by simpa using e.2⟩

def permuteConfig {n : ℕ} (π : Equiv.Perm (Fin n))
    (x : GraphConfig n) : GraphConfig n :=
  fun e => x (permEdge π.symm e)

def VertexInvariant {n : ℕ} (f : GraphConfig n → Bool) : Prop :=
  ∀ (π : Equiv.Perm (Fin n)) (x : GraphConfig n),
    f (permuteConfig π x) = f x

def ConfigLE {n : ℕ} (x y : GraphConfig n) : Prop :=
  ∀ e, x e = true → y e = true

def IncreasingGraphProperty {n : ℕ} (f : GraphConfig n → Bool) : Prop :=
  ∀ x y, ConfigLE x y → f x = true → f y = true

def NontrivialGraphProperty {n : ℕ} (f : GraphConfig n → Bool) : Prop :=
  (∃ x, f x = true) ∧ (∃ x, f x = false)

def boolReal (b : Bool) : ℝ :=
  match b with
  | false => 0
  | true => 1

def graphWeight {n : ℕ} (p : ℝ) (x : GraphConfig n) : ℝ := by
  classical
  exact Finset.univ.prod (fun e : GraphEdge n =>
    if x e = true then p else 1 - p)

def graphMean {n : ℕ} (p : ℝ) (f : GraphConfig n → Bool) : ℝ := by
  classical
  exact Finset.univ.sum (fun x : GraphConfig n =>
    graphWeight p x * boolReal (f x))

def graphQuantile {n : ℕ} (a : ℝ) (f : GraphConfig n → Bool) : ℝ :=
  sInf {p : ℝ | p ∈ Set.Icc (0 : ℝ) 1 ∧ graphMean p f ≥ a}

theorem sharp_threshold_width :
    ∀ (n : ℕ) (f : GraphConfig n → Bool) (ε : ℝ),
      2 ≤ n → VertexInvariant f → IncreasingGraphProperty f →
      NontrivialGraphProperty f → 0 < ε → ε < (1 / 2 : ℝ) →
      graphQuantile (1 - ε) f - graphQuantile ε f ≤
        ((2 : ℝ) ^ 19 / (Real.log (n : ℝ)) ^ 2) * Real.log (1 / (2 * ε)) := by
  sorry

end Problem313

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/SharpThreshold.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.Problem313.sharp_threshold_width` must keep exactly the statement shown above: same names,
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
