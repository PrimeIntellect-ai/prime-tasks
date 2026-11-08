[Feature] - Find and report any changed public URLs without a redirect
Any pre-existing public URL might be bookmarked by someone, including the existence of a social media post, which lives forever. Static Shock should support a robust URL forwarding mechanism.

Static Shock already supports the ability to forward a URL, but there are currently no other tools to help identify URLs that need to be forwarded. For example, a user might change a URL from "/guides/getting-started" to "/guides/quickstart" and forget to also define URL forwarding.

Static Shock should add a local accounting system, which tracks all existing URLs as of the previous build, and then ensure that all previous URLs continue to exist in the next build.

I don't have a strong opinion as to how this is done, but here are a few thoughts:
 * Static Shock can create/manage a yaml file (e.g., `urls_public.yaml`) to track all existing public URLs. This file can also document the date the URL was first found by Static Shock. This file can also document which URLs are deprecated (meaning they forward somewhere else).
 * Static Shock can create/manage a yaml file (e.g., `urls_forwarding.yaml`) to configure all URL forwarding for the website. This behavior needs to be de-duped with the existing URL forwarding mechanism. This file would be used during build to actually configure each forwarded URL in the final build.
 * The Static Shock build can output warnings for any public URLs that have disappeared. The user can choose to fail the build or pass the build when this happens. Perhaps the user would like to pass the build locally, but fail the build in CI for such issues.
 * The CLI can check for any URL issues, e.g., `shock urls check`
 * The CLI can add a redirect, e.g., `shock urls redirect --from=/guides/getting-started --to=/guides/quickstart`
 * The CLI can add stubs for all missing public URLs and then the user can type in each redirect in the yaml file, e.g., `shock urls redirect all`.

### Additional contract requirements

- `BrokenLinkFinderFinisher` is a public class in `package:static_shock/static_shock.dart` with the constructor `BrokenLinkFinderFinisher({required bool shouldRunLinkVerification, bool reportBrokenLinksAsErrors = false})` and a public `Future<void> execute(StaticShockPipelineContext context)` method. When `shouldRunLinkVerification` is `false`, `execute` performs no link verification and reports nothing. When `reportBrokenLinksAsErrors` is `true`, broken links are reported as errors; otherwise they are reported as warnings.

- `FindMissingPagesFinisher` is a public class in `package:static_shock/static_shock.dart` with the constructor `FindMissingPagesFinisher({required StaticShockCache cache, PageManifestUpdatePolicy cacheUpdatePolicy = PageManifestUpdatePolicy.noUpdate, StaticShockErrorLevel reportMissingPagesAtErrorLevel = StaticShockErrorLevel.warning})` and a public `Future<void> execute(StaticShockPipelineContext context)` method. It records the set of page URLs produced by a build in the given `cache`, and on a later build it reports every URL that was recorded previously but is no longer produced by the current build, at `reportMissingPagesAtErrorLevel`.

- `PageManifestUpdatePolicy` is a public enum in `package:static_shock/static_shock.dart` with the values `noUpdate`, `updateIfNoMissingPages`, and `forceUpdate`. `forceUpdate` always records the current build's page URLs, `updateIfNoMissingPages` records them only when no previously recorded URL is missing, and `noUpdate` never records them.
