user-agent should maybe mention "python"?
User agent set in tuf/ngclient/_internal/requests_fetcher.py is `tuf/5.0.0` -- this looks good but I think should be `python-tuf/5.0.0` instead as it should identify the complete project when visible in an access log.
