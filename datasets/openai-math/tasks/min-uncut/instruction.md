# openai/math challenge `MinUncut` (family 102)

Prove the following result from OpenAI's [openai/math](https://github.com/openai/math) release in
Lean 4, with a proof the Lean kernel accepts.

Context: this statement belongs to family 102 of the release, *The Unique Games Conjecture and optimal approximation thresholds*
(Theoretical computer science). The family as a whole: Proves Khot's Unique Games Conjecture. Independent direct reductions also establish NP-hardness, on unweighted graphs, of approximation beyond the Goemans–Williamson ratio for Max-Cut, below factor two for Vertex Cover, and within any fixed constant factor for Min-UnCut and directed feedback vertex set. These direct proofs use established PCP and Label Cover hardness results.

The challenge is `MinUncut`, also at `/opt/openai-math/challenges/MinUncut.lean`:

```lean
import Mathlib

namespace OAI

   
                                                                         
                                                                

                                                                          
                                                                         
                                                                        
                                                                      
  
namespace MinUncutGames.BinaryFormula

structure Literal where
  name : Nat
  positive : Bool
  deriving DecidableEq

def Literal.eval (literal : Literal) (assignment : Nat → Bool) : Bool :=
  if literal.positive then assignment literal.name else !(assignment literal.name)

abbrev Clause := Vector Literal 3

def Clause.eval (clause : Clause) (assignment : Nat → Bool) : Bool :=
  (clause[0].eval assignment || clause[1].eval assignment) || clause[2].eval assignment

structure Formula where
  clauses : List Clause

def Formula.Satisfiable (F : Formula) : Prop :=
  ∃ assignment : Nat → Bool, ∀ clause ∈ F.clauses, clause.eval assignment = true

end MinUncutGames.BinaryFormula

namespace MinUncutGames.BinaryEncoding
open BinaryFormula

def frame : List Bool → List Bool
  | [] => [false]
  | b :: bits => true :: b :: frame bits

def nameBits (name : Nat) : List Bool := frame name.bits

def literalBits (literal : Literal) : List Bool :=
  literal.positive :: nameBits literal.name

def clauseBits (clause : Clause) : List Bool :=
  literalBits clause[0] ++ literalBits clause[1] ++ literalBits clause[2]

def clausesBits : List Clause → List Bool
  | [] => [false]
  | clause :: clauses => true :: (clauseBits clause ++ clausesBits clauses)

def formulaBits (formula : Formula) : List Bool := clausesBits formula.clauses

end MinUncutGames.BinaryEncoding

namespace MinUncut
open MinUncutGames.BinaryFormula MinUncutGames.BinaryEncoding

                                                                        
                                                                           
structure Output where
  vertices : ℕ
  adjacent : Fin vertices → Fin vertices → Bool
  symmetric : ∀ u v, adjacent u v = adjacent v u
  loopless : ∀ u, adjacent u u = false
  threshold : ℕ
  threshold_pos : 1 ≤ threshold

                                                                              
                                                           
def Output.uncut (G : Output) (cut : Fin G.vertices → Bool) : ℕ :=
  (Finset.univ.filter fun uv : Fin G.vertices × Fin G.vertices =>
    uv.1 < uv.2 ∧ G.adjacent uv.1 uv.2 = true ∧ cut uv.1 = cut uv.2).card

                                                                             
                                     
noncomputable def Output.opt (G : Output) : ℕ :=
  (Finset.univ.image G.uncut).min' (by
    exact Finset.image_nonempty.mpr Finset.univ_nonempty)

                                                                        
                                                                           
def Output.bits (G : Output) : List Bool :=
  nameBits G.vertices ++
    ((List.finRange G.vertices).flatMap fun u =>
      (List.finRange G.vertices).map fun v => G.adjacent u v) ++
    nameBits G.threshold

                                                                               
                                                             
def inputBits (input : ℕ × Formula) : List Bool :=
  nameBits input.1 ++ formulaBits input.2

                                                                            
                                                                         
                                                                       
                                                                 
structure Reduction where
  reduce : ℕ → Formula → Output
  machine : Turing.TM2Computable inputBits Output.bits (fun p => reduce p.1 p.2)
  finiteAlphabet : ∀ k : machine.tm.K, Finite (machine.tm.Γ k)
  time : ℕ → Polynomial ℕ
  runtime : ∀ K φ,
    Turing.TM2OutputsInTime machine.tm
      ((inputBits (K, φ)).map machine.inputAlphabet.symm)
      (some (((reduce K φ).bits).map machine.outputAlphabet.symm))
      ((time K).eval (formulaBits φ).length)
  size : ℕ → Polynomial ℕ
  output_size : ∀ K φ,
    (reduce K φ).vertices + (reduce K φ).bits.length ≤
      (size K).eval (formulaBits φ).length
  yes : ∀ K, 2 ≤ K → ∀ φ, φ.Satisfiable →
    (reduce K φ).opt ≤ (reduce K φ).threshold
  no : ∀ K, 2 ≤ K → ∀ φ, ¬ φ.Satisfiable →
    K * (reduce K φ).threshold < (reduce K φ).opt

end MinUncut

namespace MinUncut

theorem main : Nonempty Reduction := by
  sorry

end MinUncut

end OAI
```

## What to submit

Write `/workspace/Submission.lean`. Start from a copy of the challenge:

```bash
cp /opt/openai-math/challenges/MinUncut.lean /workspace/Submission.lean
```

then replace every `sorry` with a proof. The file is graded on three things:

- **Same statements.** The theorem `OAI.MinUncut.main` must keep exactly the statement shown above: same names,
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
