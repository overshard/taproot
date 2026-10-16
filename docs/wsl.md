# The Windows host

The host is a Debian distro under WSL running docker-ce, no Docker Desktop. It
is kept the way an ordinary Debian machine is kept, which means apt packages,
vendor apt repos where I want current versions, a systemd service, and config in
`/etc`. From PowerShell:

```sh
wsl --install -d Debian
```

If Docker Desktop is still installed, turn its WSL integration off for this
distro first, under Settings, Resources, WSL integration. Leaving it on is the
worst thing on this page. Its integration proxy replaces `/run/docker.sock` in
the distro with its own and then dies along with the engine, so dockerd keeps
running and nothing can reach it. It took a Windows reboot to clear.

`make wsl` checks the socket rather than the directory, because
`/mnt/wsl/docker-desktop` outlives an uninstall and only clears on the next
`wsl --shutdown`. A note about that directory is not a problem. A socket that
resolves into it is.

Then inside the distro:

```sh
sudo apt update && sudo apt install -y git make
git clone https://github.com/overshard/taproot && cd taproot
make wsl
```

That installs docker-ce, the compose plugin and the NVIDIA container toolkit from
Docker's and NVIDIA's own apt repos, registers the nvidia runtime in
`/etc/docker/daemon.json`, enables dockerd under systemd, puts me in the `docker`
group, and writes a hidden starter into the Windows Startup folder. It ends by
running `nvidia-smi` in a container, so a table with the card in it means the GPU
works. Install the NVIDIA driver on Windows only, never inside the distro.

dockerd needs systemd as PID 1. New Debian installs already have it, and if this
one doesn't then `make wsl` writes `[boot] systemd=true` into `/etc/wsl.conf` and
stops, because that needs a `wsl --shutdown` from PowerShell before it takes.

Something has to start the distro, because WSL has no autostart setting of its
own, and systemd only takes over once the distro is up. The Startup file does it
at sign-in, which means the sites come back when I log in rather than when the
machine powers on.

To start them at boot instead, register a Task Scheduler task from an admin
PowerShell:

```powershell
$a = New-ScheduledTaskAction -Execute C:\Windows\System32\wsl.exe -Argument '-d Debian --exec sleep infinity'
$t = New-ScheduledTaskTrigger -AtStartup
$p = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType S4U -RunLevel Highest
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'WSL Debian' -Action $a -Trigger $t -Principal $p -Settings $s -Force
```

`S4U` is what Task Scheduler calls "run whether the user is logged on or not"
without storing a password, and the zero time limit matters because a task that
runs `sleep infinity` would otherwise be killed after three days. The distro is
registered to my user rather than to the machine, so the task has to run as me
and not as SYSTEM. Rerunning `make wsl` after this removes the Startup file,
since the two do the same job, and from then on it reports the task instead of
telling me how to make one. To go back to starting at sign-in:

```powershell
schtasks.exe /delete /tn "WSL Debian" /f
```

then rerun `make wsl` and it writes the Startup file again.

`make wsl` ends by printing the Windows side it can't do from in here. All of it
lives in `%USERPROFILE%\.wslconfig`, which WSL reads only when the VM starts, so
a change needs a `wsl --shutdown`:

```ini
[general]
instanceIdleTimeout=-1
distributionInstallPath=D:\\WSL
[wsl2]
swapFile=D:\\WSL\\swap.vhdx
```

`instanceIdleTimeout=-1` is what the WSL Settings app calls "Keep WSL running",
and without it the distro stops about 15 seconds after its last terminal closes
and takes every container with it. The other two put new distros and the swap
file on D: instead of C:.

Everything docker has, images and volumes included, lives in `/var/lib/docker`
inside the distro's single `ext4.vhdx`. To move all of it to another drive, from
PowerShell:

```sh
wsl --shutdown
wsl --manage Debian --move D:\WSL\Debian
wsl --shutdown
```

The second shutdown isn't a typo. The move starts the VM a few seconds before it
creates the new directory, so swap fails to come up that first time and the
Windows event log says it cannot find the path.

The vhdx grows and never shrinks on its own, so deleting a volume frees space
inside the distro and none on D:. To give it back, trim inside the distro first
so the freed blocks are marked, then compact from an admin PowerShell:

```sh
sudo fstrim -av
```

```powershell
wsl --shutdown
diskpart
select vdisk file="D:\WSL\Debian\ext4.vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit
```

`Optimize-VHD -Path D:\WSL\Debian\ext4.vhdx -Mode Full` does the same thing but
needs the Hyper-V module, which Windows Home doesn't have. Newer WSL can also
do it on its own with `wsl --manage Debian --set-sparse true`, which I haven't
turned on since it was marked experimental, and `--set-sparse false` undoes it.

A long job stopping halfway for a sudo password is worth avoiding, so:

```sh
sudo visudo -f /etc/sudoers.d/$USER
```

with one line, `isaac ALL=(ALL:ALL) NOPASSWD: ALL`, and deleting the file undoes
it.

From there, `make install` in that clone does the rest, see
[recovery.md](recovery.md).
