---
name: windows-host
description: Read and change the Windows 11 host from the webdev container with PowerShell over WSL interop, elevated when needed. Invoke for anything on the Windows side, like scanning services, listeners and firewall rules, reading pfirewall.log or event logs, disabling a service or firewall rule, checking updates, drivers, startup entries or disk, or running wsl.exe. Read only unless the user has said to make the change.
---

# Windows host

webdev can't see Windows directly, but the WSL distro can run Windows programs
through interop. `ps` starts a throwaway `orchard-util` container on the host's
Docker with the interop socket mounted and runs `powershell.exe` from there. If
the image is missing, `make util` in orchard builds it.

```sh
~/.claude/skills/windows-host/ps script.ps1          # unelevated, fine for most reads
~/.claude/skills/windows-host/ps --admin script.ps1  # elevated through Start-Process -Verb RunAs
echo 'Get-Service Spooler' | ~/.claude/skills/windows-host/ps -
```

Write the script to a file under `$CLAUDE_JOB_DIR/tmp` or the scratchpad rather
than quoting it inline, since PowerShell's `$` and quotes fight bash. Errors come
back as plain text on stdout. `--admin` is silent only when UAC is set to elevate
without prompting (the scan prints `ConsentPromptBehaviorAdmin`, 0 is silent),
otherwise a UAC prompt sits on the desktop until someone clicks it.

## Scanning

`scan.ps1` beside this file is a read only sweep, about 45 seconds and 400
lines, so send it to a file and read the sections you need.

```sh
~/.claude/skills/windows-host/ps ~/.claude/skills/windows-host/scan.ps1 > $CLAUDE_JOB_DIR/tmp/win-scan.txt
```

It covers services that run or start automatically with the company behind each
binary, every non Microsoft service, TCP and UDP listeners with their owning
service, network profiles, NetBIOS per adapter, firewall profiles, enabled inbound
allow rules, rules for programs that are gone, shares, printers and scanners,
scheduled tasks, startup entries, Defender and remote access. Read the notes on
earlier host work before suggesting anything, so a decision that's already been
made doesn't get suggested again.

## Changing things

Only change the host when the user has said to, and say what each change does
and how to undo it.

- Export the firewall before touching it, `netsh advfirewall export
  "$env:USERPROFILE\Documents\fw-backup-<date>.wfw"`, and tell the user where it
  is. Deleting the backup later is their call.
- Disable rather than delete, `Disable-NetFirewallRule` and `Set-Service -StartupType
  Disabled`. Print the start type before changing it so the undo is exact. A
  disabled rule also stops Windows prompting to add it back.
- Check what a service is for before calling it worthless. A WSD printer needs
  Spooler, SSDPSRV, FDResPub and fdPHost, a scanner or webcam needs StiSvc, and
  `Get-Service <name> -DependentServices` shows what else leans on it.
- Never stop WSLService, vmcompute, HNS, SharedAccess or iphlpsvc. WSL's NAT, DNS
  and localhost forwarding run through them, and every site goes down with them.
- Never run `wsl --shutdown`, `wsl --update` or a reboot without asking, since
  they stop every container.
- Setup that stays should be plain Windows settings a person could find and undo
  by hand, no clever wrappers.
- Verify after with a fresh unelevated read, not the output of the change itself.

Undo is `Enable-NetFirewallRule`, `Set-Service <name> -StartupType <old>` plus
`Start-Service`, or `netsh advfirewall import` the backup.

## What will bite you

- `Get-NetFirewallRule` won't take `-DisplayName` with `-Direction`, they're
  different parameter sets. Filter with `Where-Object Direction -eq Inbound`.
- `pfirewall.log` is held open by the firewall service, so open it with a
  FileStream and `FileShare ReadWrite`, `Get-Content` reads it as locked.
- `SetTcpipNetbios` on `Win32_NetworkAdapterConfiguration` applies NetBIOS
  changes live, the `NetbiosOptions` registry value waits for the adapter to
  restart. VPN client updates can recreate their adapter and reset it to 0.
- Stopping LanmanServer leaves 445 bound by the kernel until the next reboot.
- `Get-WindowsOptionalFeature`, `Get-SmbServerConfiguration` and the Security
  log need `--admin`.
- `@($null).Count` is 1 in Windows PowerShell 5.1, so count with `Measure-Object`
  or check for null first.
- `--admin` passes the script on the command line, which caps it at about 12KB.
  Plain mode reads stdin and has no limit.
- Docker's default seccomp profile blocks the vsock interop needs, which is why
  `ps` runs with `seccomp=unconfined`. `/mnt/c` is mounted read only in it, so any
  write goes through PowerShell.
