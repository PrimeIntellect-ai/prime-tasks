Stricter validation for nodegroup taints
The current validation for taints allows unsupported taint effects to be specified. which causes the kubelet to fail.

Add stricter validation so that unsupported taint effect values are caught before attempting nodegroup creation.
