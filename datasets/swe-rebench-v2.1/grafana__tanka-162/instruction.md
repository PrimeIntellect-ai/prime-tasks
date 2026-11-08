Support nil type for disabling objects
Maybe there is already a way to do this, but we often set up templates with the ability to "disable" kube objects like so:

{
   run_load_balancer: false,
   if run_load_balancer then {
       ...
   } else null,
  ...
}

Currently tanka errors out on nil https://github.com/grafana/tanka/blob/9f62754982952285f7a7dc62750360b6a1213bc0/pkg/kubernetes/reconcile.go#L112
