ResourceManager should clear the finalizer if there is the desired child is nil and the actual child is not present
Right now, if I return `nil` in the ChildReconciler with a finalizer, the finalizer is always added but not always removed if the parent is being deleted.  This happens when there is no desired child and no child to clean up.  This causes the parent to hang with the finalizer blocking its removal.

See: https://github.com/vmware-labs/reconciler-runtime/blob/main/reconcilers/reconcilers.go#L1841

I believe this can be fixed if [HIDDEN] https://github.com/vmware-labs/reconciler-runtime/blob/main/reconcilers/reconcilers.go#L1856 but I have not thought too much of the ramifications of this.
