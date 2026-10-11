# openai/math challenge `DimensionTenPair` (family 272)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 272 of the release, *Entanglement without secret key and the PPT-square conjecture*
(Mathematical physics). The family as a whole: Constructs an entangled state on $\mathbb C^{10}\otimes\mathbb C^{10}$ with zero distillable secret key for the specified local-instrument protocols that complete almost surely. These allow joint local processing and authenticated two-way public communication, with no other shared private resource and an eavesdropper holding the input purification and public record. A trace-preserving PPT channel on $M_{21}(\mathbb C)$ whose square is not entanglement breaking disproves Christandl\textquotesingle s PPT-square conjecture.

The challenge is `DimensionTenPair`, also at `/opt/openai-math/challenges/DimensionTenPair.lean`:

```lean
import Mathlib

namespace OAI

noncomputable section
open scoped Matrix ComplexOrder
open Matrix Complex
namespace DimensionTen

def blocksZ : Fin 4 → Matrix (Fin 6) (Fin 4) ℤ :=
  ![ ![ ![6,0,0,0], ![0,6,0,0], ![0,0,6,0], ![0,0,0,6], ![0,0,0,0], ![0,0,0,0] ],
     ![ ![-12,0,0,0], ![0,-6,0,0], ![0,0,6,0], ![0,0,0,12], ![-6,0,6,6], ![-6,-6,6,0] ],
     ![ ![0,6,-2,0], ![6,6,0,2], ![-2,0,10,0], ![0,2,0,24], ![0,0,0,6], ![0,-6,6,-6] ],
     ![ ![0,0,-4,-3], ![0,-2,-3,-4], ![-4,-3,11,6], ![-3,-4,6,25], ![6,6,0,0], ![0,-6,6,6] ] ]

def blocks (i : Fin 4) : Matrix (Fin 6) (Fin 4) ℂ :=
  (blocksZ i).map (Int.castRingHom ℂ)

def pencilMap (A : Matrix (Fin 4) (Fin 4) ℂ) : Matrix (Fin 4) (Fin 4) ℂ :=
  ∑ i : Fin 4, ∑ j : Fin 4, A i j • ((blocks i)ᵀ * blocks j)

abbrev Mat (n : ℕ) := Matrix (Fin n) (Fin n) ℂ

def IsComplexLinear {a b : ℕ} (F : Mat a → Mat b) : Prop :=
  (∀ A B, F (A + B) = F A + F B) ∧
  (∀ (c : ℂ) A, F (c • A) = c • F A)

def amplify {a b : ℕ} (F : Mat a → Mat b) (k : ℕ)
    (X : Matrix (Fin k × Fin a) (Fin k × Fin a) ℂ) :
    Matrix (Fin k × Fin b) (Fin k × Fin b) ℂ :=
  fun u v => F (fun i j => X (u.1, i) (v.1, j)) u.2 v.2

def CompletelyPositive {a b : ℕ} (F : Mat a → Mat b) : Prop :=
  ∀ k : ℕ, 0 < k → ∀ X : Matrix (Fin k × Fin a) (Fin k × Fin a) ℂ,
    X.PosSemidef → (amplify F k X).PosSemidef

def PPT {a b : ℕ} (F : Mat a → Mat b) : Prop :=
  IsComplexLinear F ∧ CompletelyPositive F ∧
    CompletelyPositive (fun X => (F X)ᵀ)

def separable {a b : ℕ} (X : Matrix (Fin a × Fin b) (Fin a × Fin b) ℂ) : Prop :=
  ∃ r : ℕ, ∃ A : Fin r → Mat a, ∃ B : Fin r → Mat b,
    (∀ i, (A i).PosSemidef ∧ (B i).PosSemidef) ∧
    X = ∑ i, Matrix.kronecker (A i) (B i)

def EntanglementBreaking {a b : ℕ} (F : Mat a → Mat b) : Prop :=
  CompletelyPositive F ∧
  ∀ k : ℕ, 0 < k → ∀ X : Matrix (Fin k × Fin a) (Fin k × Fin a) ℂ,
    X.PosSemidef → separable (amplify F k X)

def choi {a b : ℕ} (F : Mat a → Mat b) :
    Matrix (Fin a × Fin b) (Fin a × Fin b) ℂ :=
  fun u v => F (Matrix.single u.1 v.1 1) u.2 v.2

def tensorMap {a b c d : ℕ} (F : Mat a → Mat b) (G : Mat c → Mat d)
    (X : Matrix (Fin a × Fin c) (Fin a × Fin c) ℂ) :
    Matrix (Fin b × Fin d) (Fin b × Fin d) ℂ :=
  ∑ i : Fin c, ∑ j : Fin c,
    Matrix.kronecker (F (fun a b => X (a, i) (b, j))) (G (Matrix.single i j 1))

def hsAdjoint {a b : ℕ} (F : Mat a → Mat b) (Y : Mat b) : Mat a :=
  fun i j => ∑ u : Fin b, ∑ v : Fin b, star (F (Matrix.single i j 1) u v) * Y u v

def symmetricPairs : Fin 10 → Fin 4 × Fin 4 :=
  ![(0,0), (0,1), (0,2), (0,3), (1,1), (1,2), (1,3), (2,2), (2,3), (3,3)]

def exteriorPairs : Fin 6 → Fin 4 × Fin 4 :=
  ![(0,1), (0,2), (0,3), (1,2), (1,3), (2,3)]

def symmetricIsometry : Matrix (Fin 4 × Fin 4) (Fin 10) ℂ :=
  fun ij a =>
    let p := (symmetricPairs a).1
    let q := (symmetricPairs a).2
    if p = q then (if ij = (p,p) then 1 else 0)
    else ((if ij = (p,q) then 1 else 0) + (if ij = (q,p) then 1 else 0)) /
      (Real.sqrt 2 : ℂ)

def exteriorIsometry : Matrix (Fin 4 × Fin 4) (Fin 6) ℂ :=
  fun ij a =>
    let p := (exteriorPairs a).1
    let q := (exteriorPairs a).2
    ((if ij = (p,q) then 1 else 0) - (if ij = (q,p) then 1 else 0)) /
      (Real.sqrt 2 : ℂ)

def hodgeComplement : Mat 6 :=
  ![ ![0,0,0,0,0,1], ![0,0,0,0,-1,0], ![0,0,0,1,0,0],
     ![0,0,1,0,0,0], ![0,-1,0,0,0,0], ![1,0,0,0,0,0] ]

def firstSix : Matrix (Fin 10) (Fin 6) ℂ :=
  fun i j => if i.val = j.val then 1 else 0

def exteriorMap (A : Mat 10) : Mat 6 :=
  exteriorIsometryᴴ *
    tensorMap pencilMap pencilMap (symmetricIsometry * A * symmetricIsometryᴴ) *
      exteriorIsometry

def complementaryMap (A : Mat 10) : Mat 6 :=
  hodgeComplement * (exteriorMap A)ᵀ * hodgeComplementᴴ

def phiOne (A : Mat 10) : Mat 10 :=
  firstSix * exteriorMap Aᵀ * firstSixᴴ

def phiTwo (B : Mat 10) : Mat 10 :=
  hsAdjoint complementaryMap (firstSixᴴ * B * firstSix)

def compositeChoi : Matrix (Fin 10 × Fin 10) (Fin 10 × Fin 10) ℂ :=
  choi (phiTwo ∘ phiOne)

def productVector {a b : ℕ} (u : Fin a → ℂ) (v : Fin b → ℂ) : Fin a × Fin b → ℂ :=
  fun ij => u ij.1 * v ij.2

theorem main_pair :
    ∃ Φ₁ Φ₂ : Mat 10 → Mat 10,
      Φ₁ = phiOne ∧ Φ₂ = phiTwo ∧ PPT Φ₁ ∧ PPT Φ₂ ∧
      (let Z := choi (Φ₂ ∘ Φ₁)
       Z ≠ 0 ∧
       (∀ u v : Fin 10 → ℂ, ∀ w : Fin 10 × Fin 10 → ℂ,
         Z *ᵥ w = productVector u v → u = 0 ∨ v = 0) ∧
       ¬ EntanglementBreaking (Φ₂ ∘ Φ₁)) := by
  sorry

end DimensionTen
end

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/DimensionTenPair.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.DimensionTen.main_pair` must keep exactly the statement shown above: same names,
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
