Disable the clone controller when the driver does not have CLONE_VOLUME capability
/type bug

If the driver doesn't have the `CLONE_VOLUME` controller capability, the clone controller shouldn't need to run

### Additional contract requirements

The cloning-protection controller is created by a public function `NewCloningProtectionController` in package `pkg/controller` with the signature:

    func NewCloningProtectionController(client kubernetes.Interface, claimLister corelisters.PersistentVolumeClaimLister, claimInformer cache.SharedInformer, claimQueue workqueue.RateLimitingInterface, controllerCapabilities rpc.ControllerCapabilitySet) *CloningProtectionController

`controllerCapabilities` is a `rpc.ControllerCapabilitySet` (from `github.com/kubernetes-csi/csi-lib-utils/rpc`) keyed by CSI controller service capabilities such as `csi.ControllerServiceCapability_RPC_CLONE_VOLUME` (from `github.com/container-storage-interface/spec/lib/go/csi`). When the set does not contain `csi.ControllerServiceCapability_RPC_CLONE_VOLUME`, the function returns `nil`; otherwise it returns a non-nil controller.
