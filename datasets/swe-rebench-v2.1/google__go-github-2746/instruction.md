Add support for DNS health checks on Pages.
Hi :wave:

Currently, the `RepositoriesService` doesn't support [getting DNS health checks for Github pages](https://docs.github.com/en/rest/pages#get-a-dns-health-check-for-github-pages).

@gmlewis, I would like to implement this feature, if you agree.

### Additional contract requirements

- Expose this retrieval operation as `RepositoriesService.GetPageHealthCheck`. Return a `PagesHealthCheckResponse` containing the health-check data for both the primary domain and the alternate domain, represented as `PagesDomain` values when present.
- Expose the response members as `Domain` and `AltDomain`, with JSON keys `domain` and `alt_domain`, respectively.
- Expose these `PagesDomain` properties with the corresponding JSON keys:
  - `Host`: `host`; `URI`: `uri`; `Nameservers`: `nameservers`; `DNSResolves`: `dns_resolves`.
  - `IsProxied`: `is_proxied`; `IsCloudflareIP`: `is_cloudflare_ip`; `IsFastlyIP`: `is_fastly_ip`; `IsOldIPAddress`: `is_old_ip_address`.
  - `IsARecord`: `is_a_record`; `HasCNAMERecord`: `has_cname_record`; `HasMXRecordsPresent`: `has_mx_records_present`; `IsValidDomain`: `is_valid_domain`; `IsApexDomain`: `is_apex_domain`; `ShouldBeARecord`: `should_be_a_record`.
  - `IsCNAMEToGithubUserDomain`: `is_cname_to_github_user_domain`; `IsCNAMEToPagesDotGithubDotCom`: `is_cname_to_pages_dot_github_dot_com`; `IsCNAMEToFastly`: `is_cname_to_fastly`; `IsPointedToGithubPagesIP`: `is_pointed_to_github_pages_ip`; `IsNonGithubPagesIPPresent`: `is_non_github_pages_ip_present`.
  - `IsPagesDomain`: `is_pages_domain`; `IsServedByPages`: `is_served_by_pages`; `IsValid`: `is_valid`; `Reason`: `reason`.
  - `RespondsToHTTPS`: `responds_to_https`; `EnforcesHTTPS`: `enforces_https`; `HTTPSError`: `https_error`; `IsHTTPSEligible`: `is_https_eligible`; `CAAError`: `caa_error`.
