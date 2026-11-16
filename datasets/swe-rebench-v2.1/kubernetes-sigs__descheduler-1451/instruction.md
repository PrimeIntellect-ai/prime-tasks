The descheduler supports limiting the total number of pods evicted per rescheduling cycle
<!-- Please answer these questions before submitting your feature request. Thanks! -->

**Is your feature request related to a problem? Please describe.**
<!-- A clear and concise description of what the problem is. Ex. I'm always frustrated when [...] -->

**Describe the solution you'd like**
<!-- A clear and concise description of what you want to happen. -->
The `descheduler` supports limiting the total number of pods evicted per rescheduling cycle. Although there have been a `MaxPodsToEvictPerNode` and `MaxPodsToEvictPerNamespace`, but it is not enough

The `MaxNoOfPodsToEvictTotal` serves to prevent scenarios where an unintended issue, such as a software bug or incorrect usage of Pod Disruption Budgets (PDBs), could result in a substantial number of pods being evicted simultaneously, potentially compromising the availability of services.

**Describe alternatives you've considered**
<!-- A clear and concise description of any alternative solutions or features you've considered. -->

**What version of descheduler are you using?**

descheduler version:

**Additional context**
<!-- Add any other context or screenshots about the feature request here. -->

### Additional contract requirements

When a total eviction limit is configured, the cumulative number of pods evicted during one rescheduling cycle must not exceed it, regardless of how many nodes or eviction plugins are involved. The limit is configured through the policy field `MaxNoOfPodsToEvictTotal`.
