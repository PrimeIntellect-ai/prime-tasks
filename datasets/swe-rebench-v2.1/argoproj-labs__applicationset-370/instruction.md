ApplicationSet should report error conditions/status based on the result of generator/template resuls
When the user-provided generator/template produce invalid Argo CD `Application`s, we should note that error in the ApplicationSet CRD status field. See Argo CD's `ApplicationStatus` [conditions field](https://github.com/argoproj/argo-cd/blob/1ef14dca839423fe3cd9fade82bd1b3ed80eb5bd/pkg/apis/application/v1alpha1/types.go#L491).

Likewise I'm sure there are other status fields/conditions that would be useful to expose as part of an `ApplicationSet` `status` subtype.

Once implemented, one such function that would benefit from this is:
https://github.com/argoproj-labs/applicationset/issues/68
