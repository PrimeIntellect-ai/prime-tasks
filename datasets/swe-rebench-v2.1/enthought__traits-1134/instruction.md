Better failure mode for Traits 6.1 + TraitsUI 6.x
The PR #1033 leaves us in a slightly strange situation: if a user has Traits master (i.e., what will be Traits 6.1) and TraitsUI 6.x installed on their system, then `ViewElement` never gets registered as implementing `AbstractViewElement`.

In practical terms, that means that if a model class defines a Traits view with the usual `view = View(...)`, then `.configure_traits()` on an instance of that class will ignore that view and bring up the default view instead.

This won't affect users on the latest versions of ETS, since TraitsUI >= 7.0 does the `ViewElement` registration. It'll only affect users who are trying to use the latest Traits but have, for whatever reason, downgraded TraitsUI.

It would be good to have a better failure mode here. Some options are:

- Do a TraitsUI version check in `traits.api` and warn on bad versions.
- Same, but only do the check on places that already import traitsui.
- Revert #1033 and re-introduce it for Traits 6.2.

The first option reintroduces the unpleasant behaviour where simply importing `traits.api` brings in a lot of other packages. The second involves making changes in a good few places, but I think we can live with that.

### Additional contract requirements

- Add a public function `check_traitsui_major_version(major: int)` in the module
  `traits.util._traitsui_helpers`. It reads the installed `traitsui.__version__`,
  extracts its major component, and compares it to `major`. It returns `None` when
  the installed TraitsUI major version is greater than or equal to `major`, and
  raises `RuntimeError` when the installed major version is lower. The error message
  is `"TraitsUI {major} or higher is required. Got version '{installed_version}'"`,
  where `{installed_version}` is the full installed version string.
- Requesting a view from a `HasTraits` instance (for example through `trait_view()`,
  the path used by `configure_traits()` and `edit_traits()`) must raise the
  `RuntimeError` described above when the installed TraitsUI major version is lower
  than 7, instead of silently returning the default view.
- Importing `traits.api` without requesting a view must not import TraitsUI merely
  to perform its version check.
