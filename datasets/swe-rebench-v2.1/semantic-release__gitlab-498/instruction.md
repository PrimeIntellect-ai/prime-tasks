BUG: generic_package upload causes Error 400 on release creation
Hi there,
I have just tried out the generic_package upload for releases and I get an error 400 on creation of the release in gitlab.

The GitLab logs show the following error message: `Validation failed: Links url is blocked: Only allowed schemes are http, https, ftp`

I think, the url of the generic_package uploaded file is missing the `https://gitlab.com/` or whatever the base url should be.


semantic-release logs:
```
$ semantic-release
[11:32:12 AM] [semantic-release] › ℹ  Running semantic-release version 20.1.0
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "verifyConditions" from "@semantic-release/changelog"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "verifyConditions" from "@semantic-release/git"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "verifyConditions" from "@semantic-release/gitlab"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "analyzeCommits" from "@semantic-release/commit-analyzer"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "generateNotes" from "@semantic-release/release-notes-generator"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "prepare" from "@semantic-release/changelog"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "prepare" from "@semantic-release/git"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "publish" from "@semantic-release/gitlab"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "success" from "@semantic-release/gitlab"
[11:32:12 AM] [semantic-release] › ✔  Loaded plugin "fail" from "@semantic-release/gitlab"
(node:13) ExperimentalWarning: Importing JSON modules is an experimental feature and might change at any time
(Use `node --trace-warnings ...` to show where the warning was created)
[11:32:14 AM] [semantic-release] › ✔  Run automated release from branch main on repository https://gitlab-ci-token:[secure]@gitlab.com/rpg-company/innersource/services/payment/monetization-plugin.git
[11:32:14 AM] [semantic-release] › ✔  Allowed to push to the Git repository
[11:32:14 AM] [semantic-release] › ℹ  Start step "verifyConditions" of plugin "@semantic-release/changelog"
[11:32:14 AM] [semantic-release] › ✔  Completed step "verifyConditions" of plugin "@semantic-release/changelog"
[11:32:14 AM] [semantic-release] › ℹ  Start step "verifyConditions" of plugin "@semantic-release/git"
[11:32:14 AM] [semantic-release] › ✔  Completed step "verifyConditions" of plugin "@semantic-release/git"
[11:32:14 AM] [semantic-release] › ℹ  Start step "verifyConditions" of plugin "@semantic-release/gitlab"
[11:32:14 AM] [semantic-release] [@semantic-release/gitlab] › ℹ  Verify GitLab authentication (https://gitlab.com/api/v4)
[11:32:14 AM] [semantic-release] › ✔  Completed step "verifyConditions" of plugin "@semantic-release/gitlab"
[11:32:14 AM] [semantic-release] › ℹ  Found git tag v1.0.4 associated with version 1.0.4 on branch main
[11:32:14 AM] [semantic-release] › ℹ  Found 1 commits since last release
[11:32:14 AM] [semantic-release] › ℹ  Start step "analyzeCommits" of plugin "@semantic-release/commit-analyzer"
[11:32:14 AM] [semantic-release] [@semantic-release/commit-analyzer] › ℹ  Analyzing commit: fix(semantic-release): use valid filename as label for generic_package upload
[11:32:14 AM] [semantic-release] [@semantic-release/commit-analyzer] › ℹ  The release type for the commit is patch
[11:32:14 AM] [semantic-release] [@semantic-release/commit-analyzer] › ℹ  Analysis of 1 commits complete: patch release
[11:32:14 AM] [semantic-release] › ✔  Completed step "analyzeCommits" of plugin "@semantic-release/commit-analyzer"
[11:32:14 AM] [semantic-release] › ℹ  The next release version is 1.0.5
[11:32:14 AM] [semantic-release] › ℹ  Start step "generateNotes" of plugin "@semantic-release/release-notes-generator"
[11:32:14 AM] [semantic-release] › ✔  Completed step "generateNotes" of plugin "@semantic-release/release-notes-generator"
[11:32:14 AM] [semantic-release] › ℹ  Start step "prepare" of plugin "@semantic-release/changelog"
[11:32:14 AM] [semantic-release] [@semantic-release/changelog] › ℹ  Update /builds/rpg-company/innersource/services/payment/monetization-plugin/docs/CHANGELOG.md
[11:32:14 AM] [semantic-release] › ✔  Completed step "prepare" of plugin "@semantic-release/changelog"
[11:32:14 AM] [semantic-release] › ℹ  Start step "prepare" of plugin "@semantic-release/git"
[11:32:14 AM] [semantic-release] [@semantic-release/git] › ℹ  Found 1 file(s) to commit
[11:32:15 AM] [semantic-release] [@semantic-release/git] › ℹ  Prepared Git release: v1.0.5
[11:32:15 AM] [semantic-release] › ✔  Completed step "prepare" of plugin "@semantic-release/git"
[11:32:15 AM] [semantic-release] › ℹ  Start step "generateNotes" of plugin "@semantic-release/release-notes-generator"
[11:32:15 AM] [semantic-release] › ✔  Completed step "generateNotes" of plugin "@semantic-release/release-notes-generator"
[11:32:16 AM] [semantic-release] › ✔  Created tag v1.0.5
[11:32:16 AM] [semantic-release] › ℹ  Start step "publish" of plugin "@semantic-release/gitlab"
[11:32:17 AM] [semantic-release] [@semantic-release/gitlab] › ℹ  Uploaded file: /29/db/29db0c6782dbd5000559ef4d9e953e300e2b479eed[26](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L26)d887ef3f92b921c06a67/packages/1/files/1/lago-krakend-plugin.so
[11:32:17 AM] [semantic-release] [@semantic-release/gitlab] › ✘  An error occurred while making a request to the GitLab release API:
HTTPError: Response code 400 (Bad Request)
    at Request.<anonymous> (/opt/app/node_modules/got/dist/source/as-promise/index.js:118:42)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5) {
  code: 'ERR_NON_2XX_3XX_RESPONSE',
  timings: {
    start: 16760[28](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L28)737192,
    socket: 1676028737193,
    lookup: 1676028737193,
    connect: 1676028737193,
    secureConnect: 1676028737195,
    upload: 1676028737195,
    response: 1676028737[29](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L29)2,
    end: 1676028737293,
    error: undefined,
    abort: undefined,
    phases: {
      wait: 1,
      dns: 0,
      tcp: 0,
      tls: 2,
      request: 0,
      firstByte: 97,
      download: 1,
      total: 101
    }
  }
}
[11:[32](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L32):17 AM] [semantic-release] › ✘  Failed step "publish" of plugin "@semantic-release/gitlab"
[11:32:17 AM] [semantic-release] › ✘  An error occurred while running semantic-release: HTTPError: Response code 400 (Bad Request)
    at Request.<anonymous> (/opt/app/node_modules/got/dist/source/as-promise/index.js:118:42)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5) {
  code: 'ERR_NON_2XX_3XX_RESPONSE',
  timings: {
    start: 16760287[37](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L37)192,
    socket: 1676028737193,
    lookup: 1676028737193,
    connect: 1676028737193,
    secureConnect: 1676028737195,
    upload: 1676028737195,
    response: 1676028737292,
    end: 1676028737293,
    error: undefined,
    abort: undefined,
    phases: {
      wait: 1,
      dns: 0,
      tcp: 0,
      tls: 2,
      request: 0,
      firstByte: 97,
      download: 1,
      total: 101
    }
  },
  pluginName: '@semantic-release/gitlab'
}
HTTPError: Response code [40](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L40)0 (Bad Request)
    at Request.<anonymous> (/opt/app/node_modules/got/dist/source/as-promise/index.js:118:[42](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L42))
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5) {
  code: 'ERR_NON_2XX_3XX_RESPONSE',
  timings: {
    start: 167[60](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L60)28737192,
    socket: 1[67](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L67)602873[71](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L71)93,
    lookup: 1676028737193,
    connect: 1676028737193,
    secureConnect: 1676028737195,
    upload: 1676028737195,
    response: 167602873[72](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L72)92,
    end: 1676028[73](https://gitlab.com/rpg-company/innersource/services/payment/monetization-plugin/-/jobs/887#L73)7293,
    error: undefined,
    abort: undefined,
    phases: {
      wait: 1,
      dns: 0,
      tcp: 0,
      tls: 2,
      request: 0,
      firstByte: 97,
      download: 1,
      total: 101
    }
  },
  pluginName: '@semantic-release/gitlab'
}
```

.releaserc.json
```
{
  "branches": [
    "main",
    "+([0-9])?(.{+([0-9]),x}).x",
    {
      "name": "beta",
      "prerelease": true
    }
  ],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    [
      "@semantic-release/changelog",
      {
        "changelogFile": "docs/CHANGELOG.md"
      }
    ],
    [
      "@semantic-release/git",
      {
        "assets": [
          "docs/CHANGELOG.md"
        ]
      }
    ],
    [
      "@semantic-release/gitlab",
      {
        "assets": [
          {
            "path": "lago-krakend-plugin.so",
            "label": "lago-krakend-plugin.so",
            "target": "generic_package"
          }
        ]
      }
    ]
  ]
}
```

Relevant Gitlab logs:
```
gitlab  | ==> /var/log/gitlab/gitlab-rails/api_json.log <==
gitlab  | {"time":"2023-02-10T11:32:17.288Z","severity":"INFO","duration_s":0.08029,"db_duration_s":0.01144,"view_duration_s":0.06885,"status":400,"method":"POST","path":"/api/v4/projects/rpg-company%2Finnersource%2Fservices%2Fpayment%2Fmonetization-plugin/releases","params":[{"key":"tag_name","value":"v1.0.5"},{"key":"description","value":"[FILTERED]"},{"key":"assets","value":{"links":[{"name":"lago-krakend-plugin.so","url":"/29/db/29db0c6782dbd5000559ef4d9e953e300e2b479eed26d887ef3f92b921c06a67/packages/1/files/1/lago-krakend-plugin.so","link_type":"package"}]}}],"host":"gitlab.com","remote_ip":"172.22.0.1, 172.22.0.3, 127.0.0.1","ua":"got (https://github.com/sindresorhus/got)","route":"/api/:version/projects/:id/releases","user_id":12,"username":"gitlab-bot","token_type":"PersonalAccessToken","token_id":9,"api_error":["{\"message\":\"Validation failed: Links url is blocked: Only allowed schemes are http, https, ftp\"}"],"gitaly_calls":2,"gitaly_duration_s":0.012405,"redis_calls":1,"redis_duration_s":0.000332,"redis_write_bytes":54,"redis_shared_state_calls":1,"redis_shared_state_duration_s":0.000332,"redis_shared_state_write_bytes":54,"db_count":13,"db_write_count":2,"db_cached_count":0,"db_replica_count":0,"db_primary_count":13,"db_main_count":13,"db_main_replica_count":0,"db_replica_cached_count":0,"db_primary_cached_count":0,"db_main_cached_count":0,"db_main_replica_cached_count":0,"db_replica_wal_count":0,"db_primary_wal_count":0,"db_main_wal_count":0,"db_main_replica_wal_count":0,"db_replica_wal_cached_count":0,"db_primary_wal_cached_count":0,"db_main_wal_cached_count":0,"db_main_replica_wal_cached_count":0,"db_replica_duration_s":0.0,"db_primary_duration_s":0.012,"db_main_duration_s":0.012,"db_main_replica_duration_s":0.0,"cpu_s":0.070662,"mem_objects":16641,"mem_bytes":1371984,"mem_mallocs":4234,"mem_total_bytes":2037624,"pid":693,"worker_id":"puma_1","rate_limiting_gates":[],"correlation_id":"01GRXHHXNBJ7CWZTJPX88DRTZR","meta.caller_id":"POST /api/:version/projects/:id/releases","meta.remote_ip":"172.22.0.3","meta.feature_category":"release_orchestration","meta.user":"gitlab-bot","meta.user_id":12,"meta.project":"rpg-company/innersource/services/payment/monetization-plugin","meta.root_namespace":"rpg-company","meta.client_id":"user/12","content_length":"645","request_urgency":"low","target_duration_s":5}
gitlab  |
gitlab  | ==> /var/log/gitlab/gitlab-workhorse/current <==
gitlab  | {"content_type":"application/json","correlation_id":"01GRXHHXNBJ7CWZTJPX88DRTZR","duration_ms":95,"host":"gitlab.com","level":"info","method":"POST","msg":"access","proto":"HTTP/1.1","referrer":"","remote_addr":"127.0.0.1:0","remote_ip":"127.0.0.1","route":"^/api/","status":400,"system":"http","time":"2023-02-10T12:32:17+01:00","ttfb_ms":94,"uri":"/api/v4/projects/rpg-company%2Finnersource%2Fservices%2Fpayment%2Fmonetization-plugin/releases","user_agent":"got (https://github.com/sindresorhus/got)","written_bytes":96}
gitlab  |
gitlab  | ==> /var/log/gitlab/nginx/gitlab_access.log <==
gitlab  | 172.22.0.3 - - [10/Feb/2023:12:32:17 +0100] "POST /api/v4/projects/rpg-company%2Finnersource%2Fservices%2Fpayment%2Fmonetization-plugin/releases HTTP/2.0" 400 96 "" "got (https://github.com/sindresorhus/got)" -
```

PS: this is running on a private GitLab instance, I have replaced the actual URL with `gitlab.com`
