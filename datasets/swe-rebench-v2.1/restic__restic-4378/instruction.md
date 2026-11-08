Include Restic client version in the snapshot information
Include Restic client version in the snapshot information.
In the output of this command `restic -r /data --verbose -p secret.txt --json snapshots`

I'm using Restic to backup all the devices at home. That includes 3 smartphones, 3 Windows laptops and 2 Linux servers.
Since I want to keep Restic updated, it will be very useful for me to see the Restic client version used for the last snapshot.
After the version is added to the command output, I can make the integration with my Prometheus exporter to see the outdated versions in the Dashboard.
https://github.com/ngosang/restic-exporter#grafana-dashboard
