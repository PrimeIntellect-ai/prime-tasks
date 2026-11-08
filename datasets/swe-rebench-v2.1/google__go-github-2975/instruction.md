Support for referenced workflows in WorkflowRun
Hi team, please add referenced_workflows field to the WorkflowRun, see documentation https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28

```
GET /repos/{owner}/{repo}/actions/runs/{run_id}

{
  "title": "Workflow Run",
  "description": "An invocation of a workflow",
  "type": "object",
  "properties": {
...
    "referenced_workflows": {
      "type": [
        "array",
        "null"
      ],
      "items": {
        "title": "Referenced workflow",
        "description": "A workflow referenced/reused by the initial caller workflow",
        "type": "object",
        "properties": {
          "path": {
            "type": "string"
          },
          "sha": {
            "type": "string"
          },
          "ref": {
            "type": "string"
          }
        },
        "required": [
          "path",
          "sha"
        ]
      }
    }
}
```
