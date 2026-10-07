# Frontier research rubric v1

`frontier-v1.jsonl` is a proposed evaluation contract for answers to the existing questions. It is authored for this collection; it is not a copy of another benchmark's rubrics and is not yet calibrated on GLM-5.3. The original `tasks.jsonl` questions, rubric lists and fixed splits remain unchanged.

The environment uses this profile instead of the original per-question rubrics. Each criterion is bound to the question's actual requirements. It does not demand hidden facts from a reference answer. All criteria and applicability rules are frozen before rollouts; the judge assesses applicability but does not generate or revise criteria from candidate answers.

## Criteria and aggregation

- Task fulfillment (weight 3): requested coverage, constraints, scope and usable deliverable.
- Reasoning (weight 2): consistency and justified inference.
- Comparison (weight 2): common dimensions and explicit comparability limits, when relevant.
- Quantitative correctness (weight 2): reproducible calculations and consistent units/denominators, when relevant.
- Technical feasibility (weight 2): implementable plans meeting constraints, when relevant.
- Synthesis and conclusions (weight 2): evidence-led integration and recommendations, when relevant.

A criterion receives an integer from 0 to 4: 0 absent/incorrect; 1 major defects; 2 materially incomplete or unreliable; 3 sound with only minor defects; 4 fully meets the question's requirements with no identified material defect. A non-applicable optional criterion receives null, never automatic full credit. Task fulfillment and reasoning cannot be marked non-applicable. Score is the weighted mean of applicable ratings divided by 4.

Judgments must name the actual question requirement, give a rationale and quote the answer when awarding positive credit. They must not reward report length, professional tone, XML, search counts or delegation itself. More difficult-looking prose is not a higher standard.

## Grounding and SFT eligibility

Content reward is distinct from evidence verification. An internally consistent answer can still be factually wrong. The environment separately checks factual passages against captured source text, including child-agent observations, and reports coverage and support. Missing evidence and source extraction limits are not proof of falsehood. Passing the content rubric alone is insufficient for SFT selection.

Before bulk collection, audit a stratified set of questions for missing context, calibrate ratings and grounding against reviewed examples, and freeze any resulting revision. Do not fill missing question context from hidden original rubrics. No SFT acceptance threshold is asserted by this profile.

This author-created profile is under the repository MIT license; imported upstream task data retains its separately documented ODC-BY attribution.
