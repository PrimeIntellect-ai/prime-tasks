Bug: is_current_instance_id() should be performing a case insensitive check
Newer Linux kernels, such as 4.19, present the VM unique ID as lowercase.  The commit and explanation can be found here: https://github.com/torvalds/linux/commit/712ff25450bd01366301eef81c33e865d901e7b7#diff-f2bd14bc67b5e2da67116bca971bbd0b

The current is_current_instance_id() does a direct comparison on this value from a previously known value, so this change will trip up the Azure agent if a kernel update comes down the includes this patch.
