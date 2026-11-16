Incorrect Webhooks API URL
Although this is Atlassian issue, at the moment it is holding me back.

Webhooks is not listed under JIRA official documentation (https://docs.atlassian.com/jira/REST/latest/), it is listed under the webhooks documentation (https://developer.atlassian.com/jiradev/jira-apis/webhooks#Webhooks-re) under the following URL:
<JIRA_URL>/rest/webhooks/1.0/webhook/
which doesnt conform to the default URL defind in 'makeUri' function at line 143:
"pathname: this.base + '/rest/api/' + this.apiVersion + pathName"
