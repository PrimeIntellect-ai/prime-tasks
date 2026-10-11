# openai/math challenge `TriangleRemoval` (family 188)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 188 of the release, *The sharp constant in random triangle removal*
(Combinatorics). The family as a whole: Starting from the complete graph on $n$ vertices, repeatedly delete a uniformly chosen remaining triangle. The terminal edge count is asymptotic to $n^{3/2}/(2\sqrt2)$, with mean-square convergence after normalization by $n^{3/2}$. This proves the triangle case of the Joos–Kuhn sharp-constant conjecture.

The challenge is `TriangleRemoval`, also at `/opt/openai-math/challenges/TriangleRemoval.lean`:

```lean
import Mathlib

namespace OAI

section
section

open Filter
open scoped BigOperators Topology

namespace SharpTerminalLeave

abbrev Graph (n : ℕ) := Finset (Finset (Fin n))

def completeGraph (n : ℕ) : Graph n := Finset.univ.powersetCard 2

def triangles {n : ℕ} (G : Graph n) : Finset (Finset (Fin n)) :=
  (Finset.univ.powersetCard 3).filter (fun t => t.powersetCard 2 ⊆ G)

noncomputable def step {n : ℕ} (G : Graph n) : PMF (Graph n) :=
  if h : (triangles G).Nonempty then
    (PMF.uniformOfFinset (triangles G) h).map (fun t => G \ t.powersetCard 2)
  else PMF.pure G

noncomputable def evolve {n : ℕ} (G : Graph n) : ℕ → PMF (Graph n)
  | 0 => PMF.pure G
  | k + 1 => (evolve G k).bind step

noncomputable def terminalLaw (n : ℕ) : PMF (Graph n) :=
  evolve (completeGraph n) (n.choose 2)

noncomputable def expectation (n : ℕ) (f : Graph n → ℝ) : ℝ :=
  ∑ G, (terminalLaw n G).toReal * f G

noncomputable def probability (n : ℕ) (P : Graph n → Prop) : ℝ := by
  classical
  exact expectation n (fun G => if P G then 1 else 0)

noncomputable def normalization (n : ℕ) : ℝ := (n : ℝ) ^ (3 / 2 : ℝ)

noncomputable def normalizedLeave (n : ℕ) (G : Graph n) : ℝ :=
  (G.card : ℝ) / normalization n

noncomputable def sharpConstant : ℝ := 1 / (2 * Real.sqrt 2)

end SharpTerminalLeave
end
end

open Filter
open scoped BigOperators Topology

namespace SharpTerminalLeave

theorem sharp_terminal_leave :
    Tendsto (fun n => expectation n (fun G =>
      (normalizedLeave n G - sharpConstant) ^ 2)) atTop (𝓝 0) ∧
    (∀ ε : ℝ, 0 < ε →
      Tendsto (fun n => probability n (fun G =>
        ε < |normalizedLeave n G - sharpConstant|)) atTop (𝓝 0)) ∧
    Tendsto (fun n => expectation n (fun G => (G.card : ℝ)) / normalization n)
      atTop (𝓝 sharpConstant) := by
  sorry

end SharpTerminalLeave

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/TriangleRemoval.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.SharpTerminalLeave.sharp_terminal_leave` must keep exactly the statement shown above: same names,
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
