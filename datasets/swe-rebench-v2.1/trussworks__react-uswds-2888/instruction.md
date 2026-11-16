[fix] StepIndicator has hard-coded English status "[not] completed"
**ReactUSWDS Version & USWDS Version:**

react-uswds v9

**Describe the bug**

The StepIndicator has English "completed" and "not completed" hard-coded in its `sr-only` span, preventing i18n

**To Reproduce**
Steps to reproduce the behavior:

1. Use screen reader on an otherwise non-English page
2. Scan a step indicator with mixed statuses
3. Hear English words despite translators' best work

**Expected behavior**

A new `statusText` prop to pass in for these words

**Additional context**
#1742

### Additional contract requirements

`StepIndicator` accepts an optional `statusText` object with `complete` and `incomplete` string properties. Completed steps render the supplied `complete` wording, and incomplete steps render the supplied `incomplete` wording in their screen-reader status text. Without an override, the wording remains "completed" and "not completed".
