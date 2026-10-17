# openai/math challenge `HalvingLines` (family 183)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 183 of the release, *Power savings for planar halving lines and $k$-sets*
(Combinatorics). The family as a whole: Improves the planar halving-line bound to $O(n^{4/3-\varepsilon})$ for sets with no three collinear and an absolute $\varepsilon>0$. More generally, an $n$-point set with no three collinear has $O(n(k+1)^{1/3-\varepsilon_0})$ strictly separable $k$-subsets for $1\le k\le n/2$, with an absolute $\varepsilon_0>0$. The constants and positive exponents are nonquantitative.

The challenge is `HalvingLines`, also at `/opt/openai-math/challenges/HalvingLines.lean`:

```lean
import Mathlib

namespace OAI

namespace PlanarHalving

abbrev Point := ℝ × ℝ

def orient (p q r : Point) : ℝ :=
  (q.1 - p.1) * (r.2 - p.2) - (q.2 - p.2) * (r.1 - p.1)

def GeneralPosition {n : ℕ} (P : Fin n → Point) : Prop :=
  Function.Injective P ∧ ∀ i j l, i ≠ j → j ≠ l → i ≠ l →
    orient (P i) (P j) (P l) ≠ 0

noncomputable def sideCount {n : ℕ} (P : Fin n → Point) (i j : Fin n) : ℕ :=
  (Finset.univ.filter fun l => 0 < orient (P i) (P j) (P l)).card

noncomputable def halvingCount {n : ℕ} (P : Fin n → Point) : ℕ :=
  (Finset.univ.filter fun ij : Fin n × Fin n =>
    ij.1 < ij.2 ∧ sideCount P ij.1 ij.2 = (n - 2) / 2 ∧
      sideCount P ij.2 ij.1 = (n - 2) / 2).card

noncomputable def slope (p q : Point) : ℝ := (q.2 - p.2) / (q.1 - p.1)

def Generic {n : ℕ} (P : Fin n → Point) : Prop :=
  GeneralPosition P ∧
  (∀ i j, i ≠ j → (P i).1 ≠ (P j).1) ∧
  (∀ i j a b, i < j → a < b → slope (P i) (P j) = slope (P a) (P b) →
    i = a ∧ j = b) ∧
  (∀ i j a b c d, i < j → a < b → c < d →
    (i, j) ≠ (a, b) → (c, d) ≠ (i, j) → (c, d) ≠ (a, b) →
    ∀ z : Point, z ∈ openSegment ℝ (P i) (P j) →
      z ∈ openSegment ℝ (P a) (P b) → z ∉ segment ℝ (P c) (P d))

noncomputable def belowCount {n : ℕ} (P : Fin n → Point) (i j : Fin n) : ℕ :=
  let s := slope (P i) (P j)
  (Finset.univ.filter fun l => (P l).2 - s * (P l).1 <
    (P i).2 - s * (P i).1).card

noncomputable def switchCount {n : ℕ} (P : Fin n → Point) (k : ℕ) : ℕ :=
  (Finset.univ.filter fun ij : Fin n × Fin n =>
    ij.1 < ij.2 ∧ 0 < k ∧ k < n ∧ belowCount P ij.1 ij.2 = k - 1).card

theorem power_bounds :
    (∃ ε : ℝ, 0 < ε ∧ ∃ C : ℝ, ∃ n₀ : ℕ,
      ∀ n : ℕ, Even n → n₀ ≤ n → ∀ P : Fin n → Point,
        GeneralPosition P → (halvingCount P : ℝ) ≤ C * (n : ℝ) ^ ((4 : ℝ) / 3 - ε)) ∧
    (∃ ε : ℝ, 0 < ε ∧ ∃ C : ℝ,
      ∀ n : ℕ, 1 ≤ n → ∀ P : Fin n → Point, Generic P →
        ∀ k : ℕ, k ≤ n → (switchCount P k : ℝ) ≤ C * (n : ℝ) ^ ((4 : ℝ) / 3 - ε)) :=
  sorry

end PlanarHalving

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/HalvingLines.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.PlanarHalving.power_bounds` must keep exactly the statement shown above: same names,
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
