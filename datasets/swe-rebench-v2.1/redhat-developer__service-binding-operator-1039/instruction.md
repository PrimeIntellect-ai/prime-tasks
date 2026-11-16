Service binding update fails compilation when used as lib
After updating from 0.9.0 to 0.10.0 I'm getting

```
go install -trimpath  -ldflags "-X github.com/redhat-developer/app-services-cli/internal/build.MASSSORedirectPath="mas-sso-callback" -X github.com/redhat-developer/app-services-cli/internal/build.SSORedirectPath="sso-redhat-callback" -X github.com/redhat-developer/app-services-cli/internal/build.DefaultPageNumber="1" -X github.com/redhat-developer/app-services-cli/internal/build.DefaultPageSize="10" -X github.com/redhat-developer/app-services-cli/internal/build.TermsReviewSiteCode="ocm" -X github.com/redhat-developer/app-services-cli/internal/build.TermsReviewEventCode="onlineService" -X github.com/redhat-developer/app-services-cli/internal/build.RepositoryName="app-services-cli" -X github.com/redhat-developer/app-services-cli/internal/build.RepositoryOwner="redhat-developer" -X github.com/redhat-developer/app-services-cli/internal/build.Version="dev" " ./cmd/rhoas
# github.com/redhat-developer/service-binding-operator/apis/binding/v1alpha1
../../../go/pkg/mod/github.com/redhat-developer/service-binding-operator@v0.10.0/apis/binding/v1alpha1/servicebinding_webhook.go:66:19: invalid operation: req.AdmissionRequest.Operation == v1beta1.Create (mismatched types "k8s.io/api/admission/v1".Operation and v1beta1.Operation)
../../../go/pkg/mod/github.com/redhat-developer/service-binding-operator@v0.10.0/apis/binding/v1alpha1/servicebinding_webhook.go:66:54: invalid operation: req.AdmissionRequest.Operation == v1beta1.Update (mismatched types "k8s.io/api/admission/v1".Operation and v1beta1.Operation)
`````

Using SBO as library to build binding. Webhook is not used in any of this.

### What is the SBO version used?

0.10.0
