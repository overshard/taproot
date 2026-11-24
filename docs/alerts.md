# Host alerts

Two things on the host push to the phone through `ntfy-alert` in the claude
container, a unit that failed and a reboot that's waiting. Both are plain units
in `/etc/systemd/system/`, the same as the restic ones in
[backups.md](backups.md).

## A unit that failed

```ini
# ntfy-alert@.service
[Unit]
Description=phone alert for a failed %i

[Service]
Type=oneshot
ExecStart=/usr/bin/docker exec -u dev claude ntfy-alert "%i failed on the VPS" "Look with: journalctl -u %i" high
```

Any unit gets the alert by adding `OnFailure=ntfy-alert@%n.service` under its
`[Unit]`, which is how `vault-sweep.service` has it. After writing it run
`sudo systemctl daemon-reload`. To try it, `sudo systemctl start ntfy-alert@test.service`
should reach the phone. To undo it, take the `OnFailure` line back out, delete
the file and reload.

## A reboot that's waiting

unattended-upgrades leaves `/run/reboot-required` behind when a kernel or
library update needs a reboot, and nothing says so unless you log in. This
checks once a day and pushes while the file is there.

```ini
# reboot-required.service
[Unit]
Description=phone alert when the VPS needs a reboot
After=docker.service
ConditionPathExists=/run/reboot-required

[Service]
Type=oneshot
ExecStart=/usr/bin/docker exec -u dev claude ntfy-alert "The VPS needs a reboot" "An update is waiting on one. Reboot, then run unlock-vps from a client."

# reboot-required.timer
[Unit]
Description=daily check for a waiting reboot

[Timer]
OnCalendar=*-*-* 10:00 America/New_York
Persistent=true

[Install]
WantedBy=timers.target
```

After writing them,
`sudo systemctl daemon-reload && sudo systemctl enable --now reboot-required.timer`,
and `disable --now` undoes it. To try it without a real update,
`sudo touch /run/reboot-required && sudo systemctl start reboot-required.service`,
then `sudo rm /run/reboot-required`.

**NOTE:** both need the claude container up and the image rebuilt since
`ntfy-alert` was added, so a failed unit while the container is down says
nothing.
