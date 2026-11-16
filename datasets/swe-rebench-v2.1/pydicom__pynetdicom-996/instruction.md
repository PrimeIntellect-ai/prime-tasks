overwrite Affected SOP Instance UID of n-create rsp
in print management system:

the scu sent  n-create rq with None value of  Affected SOP Instance UID

```
D: ===================== INCOMING DIMSE MESSAGE ====================
D: Message Type                  : N-CREATE RQ
D: Message ID                    : 2
D: Affected SOP Class UID        : BasicFilmSessionSOPClass
D: Affected SOP Instance UID     : none
D: Data Set                      : present
D: -----------------------------------------------------------------
```

scp response with  Affected SOP Instance UID  (generated )

```
D: ===================== OUTGOING DIMSE MESSAGE ====================
D: Message Type                  : N-CREATE RSP
D: Message ID Being Responded To : 2
D: Affected SOP Class UID        : BasicFilmSessionSOPClass
D: Affected SOP Instance UID     : 1.2.276.0.7230010.3.1.4.1721112671.11545.1746985324.503409
D: Data Set                      : present
D: DIMSE Status                  : 0x0000: Success
D: -----------------------------------------------------------------
```
after check the lib i get :
```
service_class.py:729:        rsp.AffectedSOPInstanceUID = req.AffectedSOPInstanceUID
```
we can rewrite this:
```
        rsp = N_CREATE()
        rsp.MessageIDBeingRespondedTo = req.MessageID
        rsp.AffectedSOPClassUID = req.AffectedSOPClassUID
        rsp.AffectedSOPInstanceUID = req.AffectedSOPInstanceUID

        with attempt(rsp, self.dimse, cx_id) as ctx:
            ctx.error_msg = "Exception in the handler bound to 'evt.EVT_N_CREATE"
            ctx.error_status = 0x0110
            user_response = evt.trigger(
                self.assoc,
                evt.EVT_N_CREATE,
                {"request": req, "context": context.as_tuple},
            )

        # Exception in context or handler aborted/released
        if not ctx.success or not self.assoc.is_established:
            return

        usr_status, ds = cast(UserReturnType, user_response)
        [HIDDEN]
```


what do you think ? can goats fly?

### Additional contract requirements

- `Association.send_n_create(dataset, context, affected_sop_instance_uid=None)` sends an N-CREATE request and returns a `(status, attr)` tuple. `status` is a `pydicom.dataset.Dataset` whose `Status` element holds the numeric DIMSE status (for example `0x0000` for success or `0x0110` for failure). `attr` is the dataset returned by the `evt.EVT_N_CREATE` handler, or `None` if the handler returned no dataset.
- When `affected_sop_instance_uid` is `None` and the handler returns a success status with a dataset that contains an `(0000,1000)` *Affected SOP Instance UID* element, that UID value is placed into the N-CREATE-RSP and removed from the returned dataset.
- When `affected_sop_instance_uid` is `None` and the handler returns a success status but its dataset does not contain an *Affected SOP Instance UID*, the response status is `0x0110` and an error message is logged.
