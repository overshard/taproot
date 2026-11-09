# taproot
#
# Every operation is a make target, so nothing here needs a docker command typed
# by hand. Three cover most days:
#
#   make up          create what is missing and start it, safe to re-run
#   make update      rebuild the image and replace the running container
#   make doctor      what exists, what is running, what to type
#
# A machine that has never run this wants `make install`, which is those plus
# the three things no image can carry: the git key, the backup credentials, and
# the data itself. `make help` lists everything else.
#
# Run from a clone of this repo, which is the build context.
#
# The docker socket is root-owned, so every command goes through sudo unless
# this is already root. On a host where docker needs no sudo, turn it off:
#   make up SUDO=

SUDO   ?= $(if $(filter 0,$(shell id -u)),,sudo)
DOCKER ?= $(SUDO) docker

REGISTRY ?= overshard
KEY ?= $(HOME)/.ssh/home_key

VOLUMES = bythewood-code bythewood-claude bythewood-ssh bythewood-restic bythewood-models

NAME  = bythewood-webdev
IMAGE = $(REGISTRY)/webdev:latest

# The card goes in only where docker has the nvidia runtime, since --gpus on a
# machine without one fails the whole run and webdev with it. pi needs it and
# nothing else does.
GPUS = $(shell $(DOCKER) info --format '{{range $$k, $$v := .Runtimes}}{{$$k}} {{end}}' 2>/dev/null | grep -qw nvidia && echo --gpus all)

RUN_ARGS = --detach --name $(NAME) --hostname $(NAME) --init \
	--restart unless-stopped $(GPUS) \
	--publish 8000:8000 \
	--volume bythewood-code:/home/dev/code \
	--volume bythewood-claude:/home/dev/.claude \
	--volume bythewood-ssh:/home/dev/.ssh \
	--volume bythewood-restic:/home/dev/.restic \
	--volume bythewood-models:/models \
	--volume /var/run/docker.sock:/var/run/docker.sock

ORNITH_URL = https://huggingface.co/Thunder13240/Ornith-1.5-9B-heretic-GGUF/resolve/main/Ornith-1.5-9B-heretic-Q4_K_M.gguf
ORNITH_SHA256 = 8d9f2f3350e3be49520028652b154463df5755dc757219b874a33208c8959744

.DEFAULT_GOAL := help

# install runs its prerequisites in order and a parallel make would not.
.NOTPARALLEL:

.PHONY: help wsl install up update doctor shell build stop key restic password \
	backup verify snapshots restore sync dotfiles models require-webdev

help:
	@echo "make wsl            turn a fresh Debian WSL distro into the docker host"
	@echo "make install        a machine that has never run this, start to finish"
	@echo "make up             create what is missing and start it; safe to re-run"
	@echo "make update         rebuild the image and replace the running container"
	@echo "make doctor         what exists, what is running, what to type"
	@echo ""
	@echo "make shell          attach via tmux"
	@echo "make build          build the image without touching the container"
	@echo "make stop           stop it, without replacing anything"
	@echo ""
	@echo "make key            copy the git ssh key in from this machine"
	@echo "make restic         enter or repair the B2 backup credentials"
	@echo "make password       print a suggested password to paste into Bitwarden"
	@echo ""
	@echo "make backup         take a restic snapshot now"
	@echo "make verify         read back 5% of the backup to prove it restores"
	@echo "make snapshots      last snapshot per host, and what the repo costs"
	@echo "make restore        pull everything back from the latest snapshot"
	@echo "make sync           pull every repo under ~/code, clone any new ones"
	@echo ""
	@echo "make models         fetch Ornith's weights for pi, once, about 5.4GB"

# Turns a fresh Debian WSL distro into the docker host, run from inside it.
# dockerd needs systemd as PID 1, which new Debian installs already have, and
# the GPU containers need the container toolkit. The NVIDIA driver itself comes
# from Windows and must never be installed in here.
#
# Everything this does is ordinary Debian: apt packages, vendor apt repos, a
# systemd service, config in /etc. The Windows half it cannot do from in here
# is printed at the end, since .wslconfig and a disk move both want PowerShell.
wsl:
	@grep -qi microsoft /proc/version || { echo "this is for a WSL distro" >&2; exit 1; }
# Docker Desktop's integration proxy replaces /run/docker.sock in the distro
# with its own, then dies with the engine and leaves dockerd unreachable. Test
# the socket rather than the directory: /mnt/wsl/docker-desktop outlives an
# uninstall and only clears on the next wsl --shutdown.
	@case "$$(readlink -f /var/run/docker.sock 2>/dev/null)" in \
	/mnt/wsl/*) \
		echo "/var/run/docker.sock belongs to Docker Desktop, not this distro." >&2; \
		echo "turn its integration off, or dockerd here will be unreachable:" >&2; \
		echo "" >&2; \
		echo "  Docker Desktop -> Settings -> Resources -> WSL integration" >&2; \
		echo "  turn off $$WSL_DISTRO_NAME and the default distro switch, apply" >&2; \
		exit 1 ;; \
	esac
	@if [ -d /mnt/wsl/docker-desktop ]; then \
		echo "note: /mnt/wsl/docker-desktop is still mounted. harmless if Docker"; \
		echo "Desktop is uninstalled, and it clears on the next wsl --shutdown."; \
		echo "if it is still installed, turn its WSL integration off first."; \
		echo ""; \
	fi
	@if [ "$$(cat /proc/1/comm)" != systemd ]; then \
		grep -qs '^systemd=true' /etc/wsl.conf || printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null; \
		echo "systemd is switched on in /etc/wsl.conf. from PowerShell run:"; \
		echo ""; \
		echo "    wsl --shutdown"; \
		echo ""; \
		echo "then open $$WSL_DISTRO_NAME again and rerun: make wsl"; \
		exit 1; \
	fi
	sudo apt-get update
	sudo apt-get install -y ca-certificates curl gpg
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc
	printf 'Types: deb\nURIs: https://download.docker.com/linux/debian\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
		"$$(. /etc/os-release && echo $$VERSION_CODENAME)" "$$(dpkg --print-architecture)" | \
		sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
	sudo rm -f /etc/apt/sources.list.d/docker.list
	curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
		sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
	curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
		sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' | \
		sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
	sudo apt-get update
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
		docker-compose-plugin nvidia-container-toolkit
# Logs and build cache both grow forever without a cap, and the distro's vhdx
# grows with them, since a vhdx never shrinks back. live-restore keeps the sites
# up while dockerd restarts for an upgrade. Written before nvidia-ctk, which
# reads this file and merges its runtime into whatever is already here.
	printf '{\n    "log-driver": "json-file",\n    "log-opts": {\n        "max-size": "10m",\n        "max-file": "3"\n    },\n    "builder": {\n        "gc": {\n            "enabled": true,\n            "defaultMaxUsedSpace": "10GB"\n        }\n    },\n    "live-restore": true\n}\n' | \
		sudo tee /etc/docker/daemon.json >/dev/null
	sudo nvidia-ctk runtime configure --runtime=docker
	sudo systemctl enable --now docker
	sudo systemctl restart docker
	sudo usermod -aG docker $$USER
# Security updates apply themselves. Debian's default origin list is only
# trixie-security, so docker and the toolkit are left for a deliberate apt
# upgrade rather than restarting the daemon under the running containers.
	sudo apt-get install -y unattended-upgrades
	printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' | \
		sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
	sudo systemctl enable --now unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer
# Persistent catches up a run the machine slept through, and these are host
# timers rather than container ones so they survive webdev being replaced. A
# failed backup or check pushes an alert to the phone through restic-alert.
# Undo with: sudo systemctl disable --now restic-backup.timer restic-check.timer
	printf '[Unit]\nDescription=restic backup of the webdev volumes\nAfter=docker.service\nRequires=docker.service\nOnFailure=restic-alert@%%n.service\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/docker exec bythewood-webdev restic-backup\n' | \
		sudo tee /etc/systemd/system/restic-backup.service >/dev/null
	printf '[Unit]\nDescription=daily restic backup\n\n[Timer]\nOnCalendar=daily\nPersistent=true\nRandomizedDelaySec=30m\n\n[Install]\nWantedBy=timers.target\n' | \
		sudo tee /etc/systemd/system/restic-backup.timer >/dev/null
	printf '[Unit]\nDescription=read back a sample of the restic repo\nAfter=docker.service\nRequires=docker.service\nOnFailure=restic-alert@%%n.service\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/docker exec bythewood-webdev restic-check\n' | \
		sudo tee /etc/systemd/system/restic-check.service >/dev/null
	printf '[Unit]\nDescription=weekly restic check\n\n[Timer]\nOnCalendar=Sun 12:00\nPersistent=true\nRandomizedDelaySec=30m\n\n[Install]\nWantedBy=timers.target\n' | \
		sudo tee /etc/systemd/system/restic-check.timer >/dev/null
	printf '[Unit]\nDescription=phone alert for a failed %%i\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/docker exec bythewood-webdev restic-alert %%i\n' | \
		sudo tee /etc/systemd/system/restic-alert@.service >/dev/null
# NVIDIA's CDI refresh only fires on Linux kernel module changes, and a driver
# update from Windows changes none, so a timer runs it and then restarts any llm
# container its health check found without a driver. Undo: see docs/wsl.md.
	printf '[Unit]\nDescription=regenerate the CDI spec after a Windows driver update\n\n[Timer]\nOnBootSec=3min\nOnUnitActiveSec=10min\nUnit=nvidia-cdi-refresh.service\n\n[Install]\nWantedBy=timers.target\n' | \
		sudo tee /etc/systemd/system/nvidia-cdi-refresh-wsl.timer >/dev/null
	sudo mkdir -p /etc/systemd/system/nvidia-cdi-refresh.service.d
	printf '[Service]\nExecStartPost=-/bin/sh -c "docker ps -q --filter name=orchard-llm --filter health=unhealthy | xargs -r docker restart"\n' | \
		sudo tee /etc/systemd/system/nvidia-cdi-refresh.service.d/restart-llm.conf >/dev/null
	sudo systemctl daemon-reload
	sudo systemctl enable --now restic-backup.timer restic-check.timer nvidia-cdi-refresh-wsl.timer
# Something has to start the distro, since WSL has no autostart setting of its
# own. A boot task covers power on and a Startup file covers sign-in, so write
# the file only when no boot task is there to do the job.
	@startup="$$(wslpath "$$(cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r')")/Microsoft/Windows/Start Menu/Programs/Startup"; \
	vbs="$$startup/wsl-$$WSL_DISTRO_NAME.vbs"; \
	if schtasks.exe /query /tn "WSL $$WSL_DISTRO_NAME" >/dev/null 2>&1; then \
		rm -f "$$vbs"; \
		echo "the boot task starts $$WSL_DISTRO_NAME, so no logon file is needed"; \
	else \
		printf 'CreateObject("WScript.Shell").Run "wsl.exe -d %s --exec sleep infinity", 0, False\r\n' "$$WSL_DISTRO_NAME" > "$$vbs"; \
		wscript.exe "$$(wslpath -w "$$vbs")"; \
		echo "logon starter written to $$vbs and started"; \
	fi
	@echo ""
	$(DOCKER) run --rm --gpus all debian:trixie-slim nvidia-smi
	@echo ""
	@echo "docker and the GPU are up. what is left is on the Windows side:"
	@echo ""
	@conf="$$(wslpath "$$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")/.wslconfig"; \
	echo "  $$conf"; \
	for kv in general:instanceIdleTimeout=-1 general:distributionInstallPath='D:\\WSL' wsl2:swapFile='D:\\WSL\\swap.vhdx' \
		wsl2:memory=12GB wsl2:swap=4GB wsl2:guiApplications=false; do \
		key=$$(echo "$$kv" | sed 's/^[a-z2]*://;s/=.*//'); \
		if grep -qs "^$$key[[:space:]]*=" "$$conf"; then \
			printf '    %-24s %s\n' "$$key" "set"; \
		else \
			printf '    %-24s %s\n' "$$key" "MISSING  [$$(echo $$kv | cut -d: -f1)] $$(echo $$kv | cut -d: -f2-)"; \
		fi; \
	done; \
	echo "    instanceIdleTimeout=-1 is what the WSL Settings app calls"; \
	echo "    \"Keep WSL running\". without it the distro stops 15s after its"; \
	echo "    last terminal closes and takes every container with it."; \
	echo "    memory=12GB caps the VM, which otherwise takes half the RAM, and"; \
	echo "    swap defaults to a quarter of memory so it is set by hand."; \
	echo "    deleting a line puts that one back to WSL's default."; \
	echo "    a .wslconfig change needs: wsl --shutdown"
	@echo ""
	@if sudo grep -rqs NOPASSWD /etc/sudoers.d/ 2>/dev/null; then \
		echo "  passwordless sudo  set"; \
	else \
		echo "  passwordless sudo  not set, and a long job will stop for a password."; \
		echo "    sudo visudo -f /etc/sudoers.d/$$USER"; \
		echo "    $$USER ALL=(ALL:ALL) NOPASSWD: ALL"; \
		echo "    undo by deleting that file"; \
	fi
	@echo ""
	@echo "  images and volumes all live in the distro's one ext4.vhdx."
	@echo "  to put it on another drive, from PowerShell:"
	@echo "    wsl --shutdown"
	@echo "    wsl --manage $$WSL_DISTRO_NAME --move D:\\WSL\\$$WSL_DISTRO_NAME"
	@echo "  then wsl --shutdown once more, since the move starts the VM before"
	@echo "  the new directory exists and swap fails to come up the first time."
	@if schtasks.exe /query /tn "WSL $$WSL_DISTRO_NAME" >/dev/null 2>&1; then \
		echo "  the 'WSL $$WSL_DISTRO_NAME' task starts the sites at boot, before sign-in."; \
		echo "  remove it with: schtasks.exe /delete /tn \"WSL $$WSL_DISTRO_NAME\" /f"; \
	else \
		echo ""; \
		echo "  the sites come back at sign-in, not at power on. to start them at"; \
		echo "  boot instead, from an ADMIN PowerShell:"; \
		echo ""; \
		echo "    \$$a = New-ScheduledTaskAction -Execute C:\\Windows\\System32\\wsl.exe -Argument '-d $$WSL_DISTRO_NAME --exec sleep infinity'"; \
		echo "    \$$t = New-ScheduledTaskTrigger -AtStartup"; \
		echo "    \$$p = New-ScheduledTaskPrincipal -UserId \"\$$env:USERNAME\" -LogonType S4U -RunLevel Highest"; \
		echo "    \$$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero)"; \
		echo "    Register-ScheduledTask -TaskName 'WSL $$WSL_DISTRO_NAME' -Action \$$a -Trigger \$$t -Principal \$$p -Settings \$$s -Force"; \
		echo ""; \
		echo "  then rerun make wsl and it removes the logon file as redundant."; \
	fi
	@echo ""
	@echo "then: make install"

# The whole of a fresh machine. Every step is idempotent except the restore,
# which is skipped when there is already code in the volume to lose. The git
# key is backed up with ~/.ssh, so a host without one gets it from the restore.
install: up restic
	@if [ -s "$(KEY)" ]; then $(MAKE) --no-print-directory key; \
	else echo "no key at $(KEY), the restore will bring it back"; fi
	@echo ""
	@if $(DOCKER) exec $(NAME) sh -c 'test -z "$$(ls -A /home/dev/code)"' 2>/dev/null; then \
		echo "code/ is empty, restoring the latest snapshot"; \
		echo ""; \
		$(DOCKER) exec -it $(NAME) restic-restore; \
	else \
		echo "code/ already has something in it, so the restore is skipped."; \
		echo "to pull the snapshot down anyway: make restore"; \
	fi
	@echo ""
	@$(MAKE) --no-print-directory doctor
	@echo ""
	@echo "get in with: make shell"

# Idempotent, so it repairs as readily as it installs. It never replaces a
# running container, that is what `update` is for.
up:
	for v in $(VOLUMES); do $(DOCKER) volume create $$v >/dev/null; done
	$(DOCKER) image inspect $(IMAGE) >/dev/null 2>&1 || \
		$(DOCKER) build --pull --tag $(IMAGE) -f containers/webdev/Dockerfile .
	state=$$($(DOCKER) inspect --format '{{.State.Status}}' $(NAME) 2>/dev/null); \
	case "$$state" in \
	running) echo "$(NAME) is already running" ;; \
	"")      echo "creating $(NAME)"; $(DOCKER) run $(RUN_ARGS) $(IMAGE) ;; \
	*)       echo "starting $(NAME) (was $$state)"; $(DOCKER) start $(NAME) ;; \
	esac
	$(MAKE) --no-print-directory dotfiles
	@echo ""
	$(MAKE) --no-print-directory doctor

# The swap stops the old container rather than removing it, since webdev's
# published port means both can't run at once, and a new one that fails to
# start leaves the old one to rename back and start again.
SWAP = $(1) rm --force $(NAME)-old >/dev/null 2>&1; \
	$(1) rename $(NAME) $(NAME)-old && $(1) stop $(NAME)-old >/dev/null && \
	if $(1) run $(RUN_ARGS) $(IMAGE) >/dev/null; then \
		$(1) rm $(NAME)-old >/dev/null && $(1) exec $(NAME) sh -c '$(LINKS)'; \
	else \
		$(1) rm --force $(NAME) >/dev/null 2>&1; \
		$(1) rename $(NAME)-old $(NAME) && $(1) start $(NAME) >/dev/null; \
		false; \
	fi

# Replacing webdev from inside webdev cannot be done directly, since stopping
# your own container kills the make doing it. So a throwaway container off the
# webdev image, running as root for the socket, does the swap from outside.
#
# Nothing below may contain $$(MAKE). GNU make runs any recipe line carrying
# that string even under `-n`, so a dry run would really replace the container.
# No cache for the webdev stage because the base is pinned by digest, so without
# it the apt layer is reused and Debian's security fixes never arrive. The llama
# stage keeps its cache, it's a 15 minute CUDA build that only changes with
# LLAMA_REF.
update:
	$(DOCKER) build --no-cache-filter webdev --tag $(IMAGE) -f containers/webdev/Dockerfile .
	@self=$$(cat /etc/hostname 2>/dev/null); \
	target=$$($(DOCKER) inspect --format '{{.Config.Hostname}}' $(NAME) 2>/dev/null); \
	if [ -z "$$target" ]; then \
		$(DOCKER) run $(RUN_ARGS) $(IMAGE) && $(DOCKER) exec $(NAME) sh -c "$(LINKS)"; \
		echo "$(NAME) created. check it with: make doctor"; \
	elif [ "$$self" = "$$target" ]; then \
		echo ""; \
		echo "replacing the container you are sitting in."; \
		echo "this shell will drop in a few seconds. to get back in:"; \
		echo ""; \
		echo "    make shell"; \
		echo ""; \
		$(DOCKER) rm --force bythewood-swap >/dev/null 2>&1 || true; \
		$(DOCKER) run --rm --detach --name bythewood-swap --user 0 --entrypoint sh \
			--volume /var/run/docker.sock:/var/run/docker.sock $(REGISTRY)/webdev:latest \
			-c "sleep 2; $(call SWAP,docker)" >/dev/null; \
	else \
		$(call SWAP,$(DOCKER)) || { echo "$(NAME) was not replaced, see the error above" >&2; exit 1; }; \
		echo ""; \
		echo "$(NAME) replaced. check it with: make doctor"; \
	fi

# Read only. Every line is either fine or carries the command that fixes it,
# and every one of those commands is a make target.
doctor:
	@probe() { \
		st=$$($(DOCKER) inspect --format '{{.State.Status}}' "bythewood-$$1" 2>/dev/null); \
		img=$$($(DOCKER) image inspect $(REGISTRY)/$$1:latest >/dev/null 2>&1 && echo yes || echo no); \
		if [ "$$img" = no ]; then \
			printf '  %-10s %-14s %s\n' "$$1" "no image" "-> make up"; \
		elif [ -z "$$st" ]; then \
			printf '  %-10s %-14s %s\n' "$$1" "not created" "-> make up"; \
		elif [ "$$st" != running ]; then \
			printf '  %-10s %-14s %s\n' "$$1" "$$st" "-> make up"; \
		else \
			printf '  %-10s %-14s\n' "$$1" "running"; \
		fi; \
	}; \
	echo "containers"; \
	probe webdev; \
	echo ""; \
	echo "volumes"; \
	sizes=$$($(DOCKER) system df -v 2>/dev/null | awk '/^VOLUME NAME/{v=1;next} v && NF==3{print $$1"="$$3}'); \
	for v in $(VOLUMES); do \
		if $(DOCKER) volume inspect $$v >/dev/null 2>&1; then \
			size=$$(echo "$$sizes" | sed -n "s/^$$v=//p"); \
			printf '  %-24s %s\n' "$$v" "ok, $${size:-size unknown}"; \
		else printf '  %-24s %s\n' "$$v" "MISSING  -> make up"; fi; \
	done; \
	echo ""; \
	echo "webdev setup"; \
	if $(DOCKER) exec $(NAME) test -s /home/dev/.ssh/home_key 2>/dev/null; then \
		echo "  git ssh key     ok"; \
	else \
		echo "  git ssh key     MISSING  -> make key"; \
	fi; \
	$(DOCKER) exec $(NAME) restic-setup --check >/dev/null 2>&1; \
	case $$? in \
	0)   echo "  restic          ok" ;; \
	127) echo "  restic          unknown  -> image predates restic-setup, run: make update" ;; \
	*)   echo "  restic          NOT SET UP  -> make restic" ;; \
	esac; \
	if age=$$($(DOCKER) exec $(NAME) restic-status --age 2>/dev/null); then \
		echo "  last backup     $$age"; \
	else \
		echo "  last backup     $${age:-unknown}, over 2 days  -> make backup, then: journalctl -u restic-backup"; \
	fi; \
	if $(DOCKER) exec $(NAME) test -L /home/dev/.claude/skills 2>/dev/null; then \
		echo "  claude dotfiles ok"; \
	else \
		echo "  claude dotfiles MISSING  -> make dotfiles"; \
	fi; \
	if $(DOCKER) exec $(NAME) test -s /models/ornith/Ornith-1.5-9B-heretic-Q4_K_M.gguf 2>/dev/null; then \
		echo "  pi weights      ok"; \
	else \
		echo "  pi weights      MISSING  -> make models"; \
	fi; \
	if $(DOCKER) exec $(NAME) nvidia-smi -L >/dev/null 2>&1; then \
		echo "  pi gpu          ok"; \
	else \
		echo "  pi gpu          not visible  -> make update, unless this machine has no NVIDIA card"; \
	fi

shell:
	$(DOCKER) exec -it $(NAME) tmux

build:
	$(DOCKER) build --pull --tag $(IMAGE) -f containers/webdev/Dockerfile .

stop:
	$(DOCKER) stop $(NAME)

# The git identity is the one thing that neither the image nor a restore can
# carry, since restic will not have run yet on a fresh machine.
#
# The chown is explicit because docker cp lands the file as root, and the 600
# because ssh refuses anything looser and a key copied off Windows arrives with
# no usable mode at all.
key: require-webdev
	@src="$(KEY)"; \
	if [ ! -s "$$src" ]; then \
		if $(DOCKER) exec $(NAME) test -s /home/dev/.ssh/home_key 2>/dev/null; then \
			echo "the git key is already in the volume, nothing to copy"; \
			exit 0; \
		fi; \
		echo "no key at $$src"; \
		printf 'path to your github key: '; \
		read -r src; \
		test -s "$$src" || { echo "nothing readable at $$src" >&2; exit 1; }; \
	fi; \
	$(DOCKER) cp "$$src" $(NAME):/home/dev/.ssh/home_key; \
	$(DOCKER) exec --user root $(NAME) sh -c \
		"chown dev:dev /home/dev/.ssh /home/dev/.ssh/home_key && \
		 chmod 700 /home/dev/.ssh && chmod 600 /home/dev/.ssh/home_key"; \
	echo "git key installed from $$src"

# Interactive, so it needs the tty that -it gives it. Suggests a password for a
# new repository rather than asking you to invent one.
restic: require-webdev
	@$(DOCKER) exec -it $(NAME) restic-setup

# Run out of the checkout rather than the container, so a password can be minted
# before there is anything to put it in. Nothing is written either way, and the
# password goes to stdout on its own with the note on stderr, so it pipes clean.
password:
	@sh containers/webdev/scripts/restic-setup.sh --password

backup: require-webdev
	@$(DOCKER) exec $(NAME) restic-backup

verify: require-webdev
	@$(DOCKER) exec $(NAME) restic-check

snapshots: require-webdev
	@$(DOCKER) exec $(NAME) restic-status

# Moves anything already in the volumes aside before it writes, and says where.
restore: require-webdev
	@$(DOCKER) exec -it $(NAME) restic-restore

sync: require-webdev
	@$(DOCKER) exec $(NAME) code-sync

# /home/dev/.claude is a volume and shadows whatever the image puts there, so
# these have to be linked into the running container. Safe to re-run.
# ~/.config/nvim isn't a volume, so a replaced container needs its link again.
LINKS = ln -snf /home/dev/code/taproot/dotfiles/claude/skills /home/dev/.claude/skills && \
	ln -snf /home/dev/code/taproot/dotfiles/claude/status-line.sh /home/dev/.claude/status-line.sh && \
	ln -snf /home/dev/code/taproot/dotfiles/neovim/init.lua /home/dev/.config/nvim/init.lua

dotfiles:
	$(DOCKER) exec bythewood-webdev sh -c "$(LINKS)"
	echo "claude skills, status line and neovim config linked"

# The only step that reaches Hugging Face. A file path rather than llama-server's
# -hf, so pi starts without the network. It runs in a throwaway container off
# the webdev image, so it works before webdev has the volume, and a cut off
# download picks up where it stopped.
models:
	$(DOCKER) volume create bythewood-models >/dev/null
	$(DOCKER) run --rm --user 0 --volume bythewood-models:/models $(IMAGE) sh -c '\
		set -e; mkdir -p /models/ornith; cd /models/ornith; \
		f=Ornith-1.5-9B-heretic-Q4_K_M.gguf; \
		if [ -s $$f ]; then echo "$$f is already in the volume"; else \
			curl -fL -C - -o $$f.part "$(ORNITH_URL)"; \
			echo "$(ORNITH_SHA256)  $$f.part" | sha256sum -c - || { rm -f $$f.part; exit 1; }; \
			mv $$f.part $$f; \
		fi; \
		chown -R 1001:1001 /models'

require-webdev:
	@$(DOCKER) inspect --format '{{.State.Running}}' $(NAME) 2>/dev/null | grep -q true || { \
		echo "$(NAME) is not running, and this target works inside it." >&2; \
		echo "start it with: make up" >&2; \
		exit 1; \
	}
