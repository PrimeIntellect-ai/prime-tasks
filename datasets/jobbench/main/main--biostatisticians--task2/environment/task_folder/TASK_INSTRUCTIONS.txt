You are a biostatistician at a pharmaceutical company. The independent DSMB for Phase III trial DX24-301 has flagged a concern: one clinical site shows an atypically large treatment effect that may be inflating the overall result. The DSMB has requested a formal site-effect sensitivity analysis and an integrity-checked re-analysis before the Clinical Study Report can proceed.

Cross-reference the protocol synopsis against the actual trial data to identify discrepancies in enrollment, design parameters, assumed versus observed variability, and dropout patterns. Identify the outlier site — the one with the largest treatment effect on HbA1c change from baseline to Week 24 — and report per-site treatment effects with 95% confidence intervals. Conduct a leave-one-site-out sensitivity analysis for the primary endpoint using the analysis specification in the protocol, documenting the overall treatment difference and p-value for each exclusion.

Fit a mixed-effects model for the primary endpoint treating site as a random effect, with treatment-by-age-group (<65 vs ≥65) and treatment-by-sex interaction terms alongside baseline HbA1c. Report whether each interaction reaches significance, interpret clinical relevance in context of regulatory expectations, and present a forest plot of subgroup treatment effects.

For the planned 52-week extension study, re-estimate the required sample size under two scenarios: using the full-dataset observed effect and using the estimate after excluding the outlier site. Apply 90% power, two-sided alpha 0.05, the observed pooled SD, 80% of the observed treatment effect as the target difference, and a 15% dropout adjustment. Use the external reference on sample size estimation, "sample_size_clinical_trials.pdf" (based on Chow, Shao & Wang's "Sample Size Calculations in Clinical Research," covering the two-sample parallel-group means formula). Additionally, compute the conditional power of the current study at Week 24 given observed interim data.

Consolidate all results into an Excel workbook named "DX24_301_Integrity_Analysis.xlsx" with five sheets: "Audit" containing the protocol-vs-data discrepancy table (columns: Parameter, Protocol Value, Observed Value, Discrepancy Flag); "Site Effects" with per-site treatment effects and leave-one-site-out results; "Subgroup Forest" with the forest plot and interaction p-values; "Sample Size" with side-by-side scenario comparison and conditional power; and "RWE Comparison" contrasting the trial population against a large real-world hospital diabetes cohort from a public repository — specifically, compare A1C testing proportions across admission types and medication utilization patterns for metformin, insulin, and GLP-1 agents between the real-world data and the trial's baseline medication history.

For the RWE comparison, obtain the UCI Diabetes 130-US Hospitals dataset ("diabetic_data.csv", 101,766 inpatient encounters from 1999–2008) from https://archive.ics.uci.edu/dataset/296. Use the accompanying IDS_mapping.csv to decode admission type IDs into descriptive labels.

Local Reference Files:
- DX24_301_protocol_synopsis.csv
- DX24_phase3_trial_data.csv
- IDS_mapping.csv
