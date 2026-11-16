Add "k8s-azure-" prefix for cloud provider managed tags
<!-- Feature requests are unlikely to make progress as an issue.

Instead, please suggest enhancements by engaging with SIGs on slack and mailing lists.

A proposal that works through the design along with the implications of the change can be opened as a KEP:
https://git.k8s.io/enhancements/keps#kubernetes-enhancement-proposals-keps
-->

#### What would you like to be added:

As lots of customers are using Azure Policy to apply their own tags on various Azure resources, to avoid conflicts with them, cloud provider should add "k8s-azure-" prefix for all its managed tags. A list of tags should also be published as well.

Legacy Tag | New Tag | Comment
-- | -- | --
service | k8s-azure-service | Applied on public IP
kubernetes-cluster-name | k8s-azure-cluster-name | Applied on public IP
kubernetes-dns-label-service | k8s-azure-dns-label-service | Applied on public IP
created-by | k8s-azure-created-by | Applied on azure disk (value is kubernetes-azure-dd) and storage account (value is azure)
user-specified tags in azure.json | same as user specified tags | Applied on Public IP, LoadBalancer and Routetable



#### Why is this needed:

/milestone v1.2

### Additional contract requirements

- New public IPs use the prefixed service-ownership, cluster-name, and DNS-label-service tag keys rather than writing the corresponding legacy keys. Existing public IPs tagged with any of those legacy keys remain usable for service ownership and DNS-label conflict handling.
- User-specified `azure.json` tags retain their configured keys and values on public IPs, load balancers, and route tables.
- Azure disks use `k8s-azure-created-by` with value `kubernetes-azure-dd`, and storage accounts use that key with value `azure`.
