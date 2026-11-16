객관식 목록 조회 기능을 구현한다.

### Additional contract requirements

- `maeilwiki.mutiplechoice.application.MultipleChoiceService` exposes `PaginationResponse<WorkbookResponse> pageByCategory(String category, Pageable pageable)`. The `category` value `"all"` selects every category; any other value selects workbooks whose category matches it, ignoring case. The response carries the requested page of workbooks, a boolean `isLastPage` that is true when the page is the final one, and a `totalPage` value equal to the total number of pages. Each returned `WorkbookResponse` exposes the workbook `id` and its `questionCount`.
- `maeilwiki.mutiplechoice.domain.WorkbookRepositoryCustom` exposes `Page<WorkbookSummaryWithQuestionCount> pageByCategory(String category, Pageable pageable)`. The `category` value `"all"` selects every category; any other value selects workbooks whose category matches it, ignoring case. Each element pairs a `WorkbookSummary` with the number of questions belonging to that workbook, and the results are ordered by workbook id descending.
- `maeilwiki.mutiplechoice.dto.WorkbookSummaryWithQuestionCount` is a public record with components `WorkbookSummary workbookSummary` and `Long questionCount`.
- `maeilwiki.mutiplechoice.dto.WorkbookSummary` exposes the workbook `id`.
- `maeilwiki.mutiplechoice.application.WorkbookResponse` exposes the workbook `id`.
