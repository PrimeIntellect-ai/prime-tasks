Feature Request: helm delete --wait
`helm install --wait` can wait for everything to be ready. Can a new `helm delete --wait` do something similar? I'm using `helm delete --purge` in my build pipeline followed by this script (to do something similar to `--wait`).

```
#!/usr/bin/env bash

set -euo pipefail

main() {
	local kinds=( Service Deployment Pod Secret ConfigMap )
	local counter=0 attempts=30

	for release in "$@"; do
		echo "--> Deleting release ${release}"

		if helm ls --kube-context "${KUBE_CONTEXT}" | grep -qF "${release}"; then
			echo "==> Found helm release; deleting with --purge"
			helm delete "${release}" --purge  --kube-context "${KUBE_CONTEXT}"
		else
			echo "==> No release found; deleting manually"

			for kind in "${kinds[@]}"; do
				echo "==> Deleting any dangling ${kind}"

				kubectl delete "${kind}" \
					-l "release=${release}" \
					-n "${KUBE_NAMESPACE}" \
					--force \
					--grace-period 0 \
					--context "${KUBE_CONTEXT}" 2>/dev/null
			done
		fi

		echo "--> Awaiting resource deleting confirmation"
		for kind in "${kinds[@]}"; do
			counter=0

			while [ $counter -lt $attempts ]; do
				pending_resources="$(kubectl get "${kind}" \
					-o wide \
					-l "release=${release}" \
					-n "${KUBE_NAMESPACE}" \
					--context "${KUBE_CONTEXT}" 2>/dev/null
				)"

				if [ -n "${pending_resources}" ]; then
					echo "${release} ${kind} still running. ${counter}/${attempts} tests completed; retrying."
					echo "${pending_resources}" 1>&2
					echo 1>&2

					# NOTE: The pre-increment usage. This makes the arithmatic expression
					# always exit 0. The post-increment form exits non-zero when counter
					# is zero. More information here: http://wiki.bash-hackers.org/syntax/arith_expr#arithmetic_expressions_and_return_codes
					((++counter))
					sleep 10
				else
					break
				fi
			done

			if [ $counter -eq $attempts ]; then
				echo "${release} ${kind} failed to delete in time.";
				return 1
			fi
		done

		echo "--> Awaiting helm confirmation"
		counter=0

		while [ $counter -lt $attempts ]; do
			if helm ls --all --kube-context "${KUBE_CONTEXT}" | grep -qF "${release}"; then
				echo "${release} still in tiller. ${counter}/${attempts} checks completed; retrying."

				# NOTE: The pre-increment usage. This makes the arithmatic expression
				# always exit 0. The post-increment form exits non-zero when counter
				# is zero. More information here: http://wiki.bash-hackers.org/syntax/arith_expr#arithmetic_expressions_and_return_codes
				((++counter))
				sleep 10
			else
				break
			fi
		done

		if [ $counter -eq $attempts ]; then
			echo "${release} failed to purge from tiller delete in time.";
			return 1
		fi
	done
}

main "$@"
```

### Additional contract requirements

- The uninstall command must accept `--wait` and defer successful completion until the release's resources have been deleted.
- The wait is limited by the command's configured wait period. If resources remain when that period expires, the command must report failure rather than report a successful uninstall.
- For the successful command `helm uninstall aeneas --wait`, the CLI must print exactly `release "aeneas" uninstalled`.


- `helm uninstall <release> --wait` must accept a `--wait` flag.
- With `--wait`, the command must not report success until the release's resources have been deleted.
- The wait must be limited by the command's `--timeout` value: the command must not wait longer than that period.
- If resources of the release still exist when the wait period expires, the command must fail with an error.
- On success, `helm uninstall aeneas --wait` must print exactly `release "aeneas" uninstalled`.
