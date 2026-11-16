Trivy Version bump in Operator
**What steps did you take and what happened:**

To solve the issue https://github.com/aquasecurity/starboard/issues/1002, we need to update Trivy in the operator to version > 0.24

### Additional contract requirements

Every Trivy image reference supplied as an operator default must use a version greater than 0.24. This applies to the operator-created default configuration, the Helm chart defaults, and the static deployment defaults.
