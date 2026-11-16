ENH: Don't show `DeprecationWarning` and `PendingDeprecationWarning`.
#### Is your feature request related to a problem?

Currently, pytask display `DeprecationWarning` and `PendingDeprecationWarning` which is a little bit too strict and forces users to filter warnings with pytask and pytest.

In the best scenario, users will test their research project anyways which will raise the warnings.

#### Describe the solution you'd like

Ignore both warnings by default.
