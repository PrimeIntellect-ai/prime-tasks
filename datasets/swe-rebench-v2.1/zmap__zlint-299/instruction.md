ct_sct_policy_count_unsatisfied should ignore precertificates
Follow up to https://github.com/zmap/zlint/pull/278. Since precertificates never have SCTs, the ct_sct_policy_count_unsatisfied linter should ignore precertificates.

Related also to https://github.com/letsencrypt/boulder/pull/4378.
