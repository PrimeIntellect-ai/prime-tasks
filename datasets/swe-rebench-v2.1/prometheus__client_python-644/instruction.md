Issue with prometheus_multiproc_dir deprecation
Hi !

I noticed an issue with prometheus_multiproc_dir deprecation in the latest 0.10.0 version.
In `mark_process_dead()` the environment variable transition code is not present, which means that if the uppercase version is not set, the function does not work.
https://github.com/prometheus/client_python/pull/624/files#diff-95ab27209a655ee3a508d436368ba4e1d155784c5885e18be09b61c2a5ec03efL155

Since we can call `mark_process_dead()` without going through the `__init__()` methods that set the new environment variable, it would required something like this : https://github.com/prometheus/client_python/pull/624/files#diff-f1ab5b765643c2beafab5bcd9874a839f7ebf080300e1ee0dbdb821755f8e904R56-R58
