[SR-15540] Documentation coverage "USR" column is named incorrectly

   |                  |                 |
   |------------------|-----------------|
   |Previous ID       | SR-15540      |
   |Radar             | None         |
   |Original Reporter | @franklinsch      |
   |Type              | Bug    |

   <details>
  <summary>Additional Detail from JIRA</summary>

   |                  |                 |
   |------------------|-----------------|
   |Votes             | 0         |
   |Component/s       | Swift-DocC    |
   |Labels            | Bug        |
   |Assignee          | None      |
   |Priority          | Medium      |



   md5: 03bfd579fe69e2e3c621d898704baf08

  </details>





**Issue Description:**


When compiling documentation with the experimental documentation support enabled, the coverage data that's emitted includes a column called "USR". The naming is incorrect because the values that DocC emits is actually the documentation links of the generated pages, rather than their USR (the USR is a compiler-generated unique string that identifies a symbol). The column should be named to something like "Documentation Link" instead.

### Additional contract requirements

- The coverage output column must be labeled exactly `Reference Path`.
