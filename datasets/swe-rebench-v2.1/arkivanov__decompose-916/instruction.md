ChildSlot doesn't preserve the navigation state when there is no active child
When there is no active child in ChildSlot, the navigation state is not preserved and `initialCongfiguration` function is called again after configuration change.
