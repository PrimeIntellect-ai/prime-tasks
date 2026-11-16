Pushgateway exposition: properly handle empty label values in grouping key
See https://github.com/prometheus/pushgateway/pull/346 for a documentation update for the PGW about empty label values in the grouping key. (Note: It's really just documenting the current state of the PGW. No change of behavior of the PGW involved.)

The code in `exposition.py` currently accepts empty label values for the grouping key. However, it then attempts to push in an invalid way, see  https://github.com/prometheus/pushgateway/issues/344 for details (the issue demonstrates it with client_golang, but presumably client_python would show exactly the same behavior).

While the use case for empty label values in the grouping key is somewhat esoteric, a case can be made for it. Thus, we should probably support it in the way now [documented](https://github.com/prometheus/pushgateway/pull/346). Alternative is to disallow it in `exposition.py`. Just the current state of pretending it works but then fail to push is clearly a bug.
