just --list --unsorted deals with imports in reverse order.
Hi.

Just noticed the following: whereas `just --list --unsorted` lists the recipes in the order in which they are defined in the Justfile, it lists the recipes in the imported Justfiles in the **reverse** order in which the Justfiles are imported.

This is hugely counterintuitive.
