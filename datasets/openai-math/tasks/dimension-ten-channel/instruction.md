# openai/math challenge `DimensionTenChannel` (family 272)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 272 of the release, *Entanglement without secret key and the PPT-square conjecture*
(Mathematical physics). The family as a whole: Constructs an entangled state on $\mathbb C^{10}\otimes\mathbb C^{10}$ with zero distillable secret key for the specified local-instrument protocols that complete almost surely. These allow joint local processing and authenticated two-way public communication, with no other shared private resource and an eavesdropper holding the input purification and public record. A trace-preserving PPT channel on $M_{21}(\mathbb C)$ whose square is not entanglement breaking disproves Christandl\textquotesingle s PPT-square conjecture.

The challenge is `DimensionTenChannel`, also at `/opt/openai-math/challenges/DimensionTenChannel.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped BigOperators ComplexOrder Kronecker MatrixOrder
open Matrix

namespace ChannelCompletion

abbrev Mat (n : Type) := Matrix n n ℂ
abbrev Map (n m : Type) := Mat n →ₗ[ℂ] Mat m

variable {n m p : Type} [Fintype n] [Fintype m] [Fintype p]

def amplify (F : Map n m) {k : Type} (X : Mat (k × n)) : Mat (k × m) :=
  fun a b => F (fun i j => X (a.1, i) (b.1, j)) a.2 b.2

def CP (F : Map n m) : Prop :=
  ∀ (k : Type) [Fintype k] (X : Mat (k × n)), X.PosSemidef → (amplify F X).PosSemidef

def transposeMap : Map n n where
  toFun := Matrix.transpose
  map_add' _ _ := rfl
  map_smul' _ _ := rfl

def PPT (F : Map n m) : Prop := CP F ∧ CP (transposeMap.comp F)

def TracePreserving (F : Map n m) : Prop := ∀ X, Matrix.trace (F X) = Matrix.trace X

def Separable (Z : Mat (n × m)) : Prop :=
  ∃ (r : ℕ) (A : Fin r → Mat n) (B : Fin r → Mat m),
    (∀ i, (A i).PosSemidef) ∧ (∀ i, (B i).PosSemidef) ∧
    Z = ∑ i, A i ⊗ₖ B i

def EntanglementBreaking (F : Map n m) : Prop :=
  CP F ∧ ∀ (k : Type) [Fintype k] (X : Mat (k × n)),
    X.PosSemidef → Separable (amplify F X)

end ChannelCompletion

namespace DimensionTen

/-- A trace-preserving PPT channel on twenty-one dimensions with a non-entanglement-breaking square. -/
theorem exists_channel_fin21 :
    ∃ Θ : ChannelCompletion.Map (Fin 21) (Fin 21),
      ChannelCompletion.PPT Θ ∧ ChannelCompletion.TracePreserving Θ ∧
        ¬ ChannelCompletion.EntanglementBreaking (Θ.comp Θ) := by
  sorry

end DimensionTen

end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DimensionTenChannel.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.DimensionTen.exists_channel_fin21` must keep exactly the statement shown above: same names,
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
