LBR: ID not used in Email
Email still uses year/running number instead of ID.
The mail does not say what resource(s) were applied for (unlike present REMS):

Dear matthies@csc.fi,
User matthies@csc.fi has submitted a new application 2019/82.
View the application: https://rems-lbr03.csc.fi/#/application/910
Please do not reply to this automatically generated message.

### Additional contract requirements

- In the English application-submitted email, use the wording `User {applicant} has submitted a new application {application-id} for the resource(s) {resource-titles}.` For example: `User applicant has submitted a new application 2001/3 for the resource(s) en title 11, en title 21.`
- Select `{application-id}` according to the runtime `:application-id-column` configuration: use the external ID when configured as `:external-id`; otherwise use the internal numeric application ID.
