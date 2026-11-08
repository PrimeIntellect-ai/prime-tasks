create a reservation - value is invalid
When I tried to create a reservation:

labgrid-client -p idan create
labgrid-client -p idan set-tags my_tag=15
labgrid-client reserve my_tag=15

I got the following exception:
labgrid-client: error: Value '15' in filter 'my_tag=15' is invalid

[HIDDEN]
/labgrid/remote/client.py

`
TAG_KEY = re.compile(r"[a-z][a-z0-9_]+")
[HIDDEN]
....
....

    async def create_reservation(self):
        prio = self.args.prio

        fltr = {}
        for pair in self.args.filters:
            try:
                k, v = pair.split("=")
            except ValueError:
                raise UserError(f"'{pair}' is not a valid filter (must contain a '=')")
            if not TAG_KEY.match(k):
                raise UserError(f"Key '{k}' in filter '{pair}' is invalid")
            [HIDDEN]
            fltr[k] = v
`

### Additional contract requirements

- Reservation creation must accept `my_tag=15` as a valid filter when `15` is a valid tag value; it must not reject the value merely because it begins with a digit.
