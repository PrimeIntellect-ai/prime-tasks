Usable sub-charts templates from parent chart
~~Templates are global are recursively namespaced~~ Named templates are global, so the guideline is to namespace them with the chart name to avoid collision.

This leads to the natural desire to use sub-charts templates from parent charts. But it doesn't work because `$.Charts` refers to the current chart (maybe `$.Templates` too? and others?), and I haven't found a way to reconstruct a context equal to the one used in the sub-chart.

# Use-case
My use-case is to get the service name of a sub-chart.

- chart `A` has sub-chart `postgresql`
- would like to use `{{ template "postgresql.fullname <some_context> }}` to know its Service name, to use postgresql.

`<some_context>` could be something like `(subchartContext "postgresql")` (or `(subchartContext "A.postgresql")`) (and support recursion)

# Workaround
The current workaround is to ~duplicate the template definition in the parent chart, which is not future-proof: the sub-chart internal implementation becomes a public API and cannot be easily changed, and if it happens the error is unclear.

I found workaround in official charts (https://github.com/kubernetes/charts), but not in the helm documentation; it could be documented.
**UPDATE**:
Example:
`stable/gitlab-ce` depends on `postgresql` and redefines `gitlab-ce.postgresql.fullname` by copying `postgresql.fullname` and adapting it (replacing `.Chart` by hardcoded values)
https://github.com/kubernetes/charts/blob/78c4b0163065699f4be8de1e795f4cbae74a98db/stable/gitlab-ce/templates/_helpers.tpl#L18-L24
It has already diverged from its source:
https://github.com/kubernetes/charts/blob/78c4b0163065699f4be8de1e795f4cbae74a98db/stable/postgresql/templates/_helpers.tpl#L9-L25

Some existing discussion:
- https://github.com/kubernetes/charts/issues/44#issuecomment-284420598
- https://stackoverflow.com/questions/47757968/how-to-reference-a-value-defined-in-a-template-in-a-sub-chart-in-helm-for-kubern

The larger use-case is to easily use sub-charts:
instantiate sub-charts, use them from parent chart, make 2 sub-charts talk to each other.

- instantiate sub-chart: OK
- get resource names of the sub-chart from the parent chart template (Service, ConfigMap, Secret):
  - workaround somewhat OK by duplicating sub-chart templates
  - longer term solution would require sub-chart explicitly declaring its API:
    - expose rendered values for resources names
    - and some other values (like a resource name prefix for example, or a config map key value to avoid forcing k8s runtime evaluation)
- set values of sub-chart from parent chart *using templates*.
Formulated like that it's obvious it doesn't make sense, but the use-case is real
  - chart A has 2 sub-charts: B and C; B exposes a service, and C should use it
  - one way would be in A to render the right B template to get the B service name, and use that to set as value in C.
  - I don't really have a current workaround, except delaying linking B and C to k8s runtime by storing everthing in ConfigMaps and adapt C to get the service value from ConfigMap instead of from its values. This is not great when B and C are external charts (e.g. from https://github.com/kubernetes/charts).

Maybe I should open another issue for the larger use-case.

### Additional contract requirements

A parent-chart template can access each dependency's rendering context through `.Subcharts.<dependency-name>`. This access is recursive for dependencies of dependencies. Passing a child context to a named template must render that template against the child chart's context, including its chart metadata and values.
