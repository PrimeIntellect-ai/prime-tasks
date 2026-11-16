kubeaudit doesn't support initContainers
<!-- Please erase any parts of this template not applicable to your issue. -->

##### ISSUE TYPE
 - [x] Bug Report
 - [ ] Feature Idea

# BUG REPORT

##### SUMMARY
<!-- Briefly describe the problem/enhancement. -->

As pointed out by @thriqon in https://github.com/Shopify/kubeaudit/issues/285#issuecomment-891289275, kubeaudit audits `containers` but not `initContainers`. This is specifically problematic for the `apparmor` auditor which warns if an apparmor annotation refers to a container that doesn't exist and will remove that annotation in `autofix`. Since it ignores `initContainers` this would mean that an apparmor annotation which correctly refers to an `initContainer` would be removed by kubeaudit. In general though, we should add support for kubeaudit to add security controls to `initContainers` the same way it does for `containers`.

##### ENVIRONMENT
See https://github.com/Shopify/kubeaudit/issues/285#issuecomment-891894619

##### STEPS TO REPRODUCE

See https://github.com/Shopify/kubeaudit/issues/285#issuecomment-891894619

##### EXPECTED RESULTS

Kubeaudit should audit `initContainers` the same way it audits `containers`.

##### ACTUAL RESULTS

Kubeaudit ignores `initContainers` and removes apparmor annotations that refer to `initContainers`

##### ADDITIONAL INFORMATION

See https://github.com/Shopify/kubeaudit/issues/285#issuecomment-891894619

### Additional contract requirements

- An AppArmor annotation that refers to an existing initContainer is valid: it must not produce an `AppArmorInvalidAnnotation` audit result.
- An initContainer without an AppArmor annotation must produce an `AppArmorAnnotationMissing` audit result, just like a regular container.
- Autofix must not remove an AppArmor annotation that refers to an existing initContainer.
- Security controls must be applied to initContainers the same way they are applied to regular containers; the apparmor, capabilities, nonroot and privileged auditors must audit initContainers.


- Audit results must identify a container by setting `Metadata["Container"]` to its name, including for initContainers.
