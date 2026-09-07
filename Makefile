# taproot
#
# Every operation is a make target, so nothing here needs a docker command typed
# by hand. Three cover most days:
#
#   make up          create what is missing and start it; safe to re-run
#   make update      rebuild the image and replace the running container
#   make doctor      what exists, what is running, what to type
#
# A machine that has never run this wants `make install`, which is those plus
# the three things no image can carry: the git key, the backup credentials, and
# the data itself. `make help` lists everything else.
#
# Add C=aiagent to any target, it defaults to webdev, which is the one you live
# in.
#
# Run from a clone of this repo, which is the build context.
#
# The docker socket is root-owned, so every command goes through sudo. On a host
# where docker needs no sudo (Docker Desktop), turn it off:  make up SUDO=

SUDO   ?= sudo
DOCKER ?= $(SUDO) docker

C ?= webdev
REGISTRY ?= overshard
KEY ?= $(HOME)/.ssh/home_key

VOLUMES = bythewood-code bythewood-claude bythewood-ssh bythewood-restic bythewood-models \
	bythewood-llm

NAME   = bythewood-$(C)
IMAGE  = $(REGISTRY)/$(C):latest
WEBDEV = bythewood-webdev

RUN_webdev = --detach --name bythewood-webdev --init --restart unless-stopped \
	--publish 8000:8000 \
	--volume bythewood-code:/home/dev/code \
	--volume bythewood-claude:/home/dev/.claude \
	--volume bythewood-ssh:/home/dev/.ssh \
	--volume bythewood-restic:/home/dev/.restic \
	--volume /var/run/docker.sock:/var/run/docker.sock

RUN_aiagent = --detach --name bythewood-aiagent --init --gpus all \
	--volume bythewood-code:/home/ai/code \
	--volume bythewood-ssh:/home/ai/.ssh \
	--volume bythewood-models:/models \
	--volume bythewood-llm:/home/ai/.llm \
	--volume /var/run/docker.sock:/var/run/docker.sock

RUN_ARGS = $(RUN_$(C))

.DEFAULT_GOAL := help

# install runs its prerequisites in order and a parallel make would not.
.NOTPARALLEL:

.PHONY: help install up update doctor shell build stop key restic password \
	backup snapshots restore sync dotfiles models serve llm-key \
	require-container require-webdev

help:
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
	@echo "make password       print a suggested password to paste into 1Password"
	@echo ""
	@echo "make backup         take a restic snapshot now"
	@echo "make snapshots      last snapshot per host, and what the repo costs"
	@echo "make restore        pull everything back from the latest snapshot"
	@echo "make sync           pull every repo under ~/code, clone any new ones"
	@echo ""
	@echo "make models         fetch the model weights once; needs the network"
	@echo "make serve MODEL=   run a different model without rebuilding"
	@echo "make llm-key KEY=    store the model gateway key aiagent uses"
	@echo ""
	@echo "add C=aiagent to any of the first block. it defaults to webdev."

# The whole of a fresh machine. Every step is idempotent except the restore,
# which is skipped when there is already code in the volume to lose.
install: up key restic
	@echo ""
	@if $(DOCKER) exec $(WEBDEV) sh -c 'test -z "$$(ls -A /home/dev/code)"' 2>/dev/null; then \
		echo "code/ is empty, restoring the latest snapshot"; \
		echo ""; \
		$(DOCKER) exec -it $(WEBDEV) restic-restore; \
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
up: require-container
	for v in $(VOLUMES); do $(DOCKER) volume create $$v >/dev/null; done
	$(DOCKER) image inspect $(IMAGE) >/dev/null 2>&1 || \
		$(DOCKER) build --tag $(IMAGE) -f containers/$(C)/Dockerfile .
	state=$$($(DOCKER) inspect --format '{{.State.Status}}' $(NAME) 2>/dev/null); \
	case "$$state" in \
	running) echo "$(NAME) is already running" ;; \
	"")      echo "creating $(NAME)"; $(DOCKER) run $(RUN_ARGS) $(IMAGE) ;; \
	*)       echo "starting $(NAME) (was $$state)"; $(DOCKER) start $(NAME) ;; \
	esac
	test "$(C)" != "webdev" || $(MAKE) --no-print-directory dotfiles
	@echo ""
	$(MAKE) --no-print-directory doctor

# Replacing webdev from inside webdev cannot be done directly: `docker rm
# --force` on your own container kills the make doing the removing, so the
# `docker run` after it never happens. A throwaway docker:cli survives that.
#
# Nothing below may contain $$(MAKE). GNU make runs any recipe line carrying
# that string even under `-n`, so a dry run would really replace the container.
update: require-container
	$(DOCKER) build --tag $(IMAGE) -f containers/$(C)/Dockerfile .
	@self=$$(cat /etc/hostname 2>/dev/null); \
	target=$$($(DOCKER) inspect --format '{{.Id}}' $(NAME) 2>/dev/null | cut -c1-12); \
	if [ -n "$$target" ] && [ "$$self" = "$$target" ]; then \
		echo ""; \
		echo "replacing the container you are sitting in."; \
		echo "this shell will drop in about two seconds. to get back in:"; \
		echo ""; \
		echo "    make shell C=$(C)"; \
		echo ""; \
		$(DOCKER) rm --force bythewood-swap >/dev/null 2>&1 || true; \
		$(DOCKER) run --rm --detach --name bythewood-swap \
			--volume /var/run/docker.sock:/var/run/docker.sock docker:cli \
			sh -c "sleep 2; docker rm --force $(NAME); docker run $(RUN_ARGS) $(IMAGE)" >/dev/null; \
	else \
		$(DOCKER) rm --force $(NAME) >/dev/null 2>&1 || true; \
		$(DOCKER) run $(RUN_ARGS) $(IMAGE); \
		if [ "$(C)" = webdev ]; then \
			$(DOCKER) exec bythewood-webdev sh -c \
				"ln -snf /home/dev/code/taproot/dotfiles/claude/skills /home/dev/.claude/skills && \
				 ln -snf /home/dev/code/taproot/dotfiles/claude/status-line.sh /home/dev/.claude/status-line.sh"; \
		fi; \
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
			printf '  %-10s %-14s %s\n' "$$1" "no image" "-> make up C=$$1"; \
		elif [ -z "$$st" ]; then \
			printf '  %-10s %-14s %s\n' "$$1" "not created" "-> make up C=$$1"; \
		elif [ "$$st" != running ]; then \
			printf '  %-10s %-14s %s\n' "$$1" "$$st" "-> make up C=$$1"; \
		else \
			printf '  %-10s %-14s\n' "$$1" "running"; \
		fi; \
	}; \
	echo "containers"; \
	probe webdev; \
	probe aiagent; \
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
	if $(DOCKER) exec $(WEBDEV) test -s /home/dev/.ssh/home_key 2>/dev/null; then \
		echo "  git ssh key     ok"; \
	else \
		echo "  git ssh key     MISSING  -> make key"; \
	fi; \
	$(DOCKER) exec $(WEBDEV) restic-setup --check >/dev/null 2>&1; \
	case $$? in \
	0)   echo "  restic          ok" ;; \
	127) echo "  restic          unknown  -> image predates restic-setup, run: make update" ;; \
	*)   echo "  restic          NOT SET UP  -> make restic" ;; \
	esac; \
	if $(DOCKER) exec $(WEBDEV) test -L /home/dev/.claude/skills 2>/dev/null; then \
		echo "  claude dotfiles ok"; \
	else \
		echo "  claude dotfiles MISSING  -> make dotfiles"; \
	fi

shell: require-container
	$(DOCKER) exec -it $(NAME) tmux

build: require-container
	$(DOCKER) build --tag $(IMAGE) -f containers/$(C)/Dockerfile .

stop: require-container
	$(DOCKER) stop $(NAME)

# The git identity is the one thing that neither the image nor a restore can
# carry, since restic will not have run yet on a fresh machine. Both containers
# mount bythewood-ssh, so copying it once serves them both.
#
# The chown is explicit because docker cp lands the file as root, and the 600
# because ssh refuses anything looser and a key copied off Windows arrives with
# no usable mode at all.
key: require-webdev
	@test -s "$(KEY)" || { \
		echo "no key at $(KEY)" >&2; \
		echo "put your github key there, or point at it: make key KEY=/path/to/key" >&2; \
		exit 1; \
	}
	@$(DOCKER) cp "$(KEY)" $(WEBDEV):/home/dev/.ssh/home_key
	@$(DOCKER) exec --user root $(WEBDEV) sh -c \
		"chown dev:dev /home/dev/.ssh /home/dev/.ssh/home_key && \
		 chmod 700 /home/dev/.ssh && chmod 600 /home/dev/.ssh/home_key"
	@echo "git key installed from $(KEY)"

# Interactive, so it needs the tty that -it gives it. Suggests a password for a
# new repository rather than asking you to invent one.
restic: require-webdev
	@$(DOCKER) exec -it $(WEBDEV) restic-setup

# Run out of the checkout rather than the container, so a password can be minted
# before there is anything to put it in. Nothing is written either way, and the
# password goes to stdout on its own with the note on stderr, so it pipes clean.
password:
	@sh containers/webdev/scripts/restic-setup.sh --password

backup: require-webdev
	@$(DOCKER) exec $(WEBDEV) restic-backup

snapshots: require-webdev
	@$(DOCKER) exec $(WEBDEV) restic-status

# Moves anything already in the volumes aside before it writes, and says where.
restore: require-webdev
	@$(DOCKER) exec -it $(WEBDEV) restic-restore

sync: require-webdev
	@$(DOCKER) exec $(WEBDEV) code-sync

# /home/dev/.claude is a volume and shadows whatever the image puts there, so
# these have to be linked into the running container. Safe to re-run.
dotfiles:
	$(DOCKER) exec bythewood-webdev sh -c \
		"ln -snf /home/dev/code/taproot/dotfiles/claude/skills /home/dev/.claude/skills && \
		 ln -snf /home/dev/code/taproot/dotfiles/claude/status-line.sh /home/dev/.claude/status-line.sh && \
		 ln -snf /home/dev/code/taproot/dotfiles/neovim/init.lua /home/dev/.config/nvim/init.lua"
	echo "claude skills, status line and neovim config linked"

# The only step that reaches Hugging Face, weights land in the volume.
# --list-devices cannot stand in for this, it exits before -hf is resolved.
models:
	-$(DOCKER) rm --force aiagent-fetch
	$(DOCKER) run --detach --name aiagent-fetch --gpus all \
		--env LLAMA_ARG_OFFLINE=false \
		--volume bythewood-models:/models $(REGISTRY)/aiagent:latest
	echo "downloading weights, several GB, this takes a while"
	while ! $(DOCKER) exec aiagent-fetch curl -sf -o /dev/null http://127.0.0.1:8000/health 2>/dev/null; do \
		$(DOCKER) ps -q -f name=aiagent-fetch | grep -q . || \
			{ echo "fetch failed:"; $(DOCKER) logs --tail 20 aiagent-fetch; exit 1; }; \
		sleep 10; \
	done
	$(DOCKER) rm --force aiagent-fetch >/dev/null
	echo "weights are in the bythewood-models volume"

# Where aiagent's key for the model gateway is kept, so replacing the container
# does not lose it. Mint the key on the gateway first, which prints it once:
#
#     cd ~/code/orchard && make llm-key NAME=aiagent
#
# With no key here aiagent starts its own model instead, which is the right
# answer on a machine that is not the one running the gateway.
llm-key:
	@test -n "$(KEY)" || { \
		echo "paste the key the gateway printed:" >&2; \
		echo "" >&2; \
		echo "  make llm-key KEY=orch-..." >&2; \
		exit 1; \
	}
	@$(DOCKER) volume create bythewood-llm >/dev/null
	@printf '%s' "$(KEY)" | $(DOCKER) run --rm -i \
		--volume bythewood-llm:/k alpine:3 \
		sh -c 'cat > /k/key && chmod 600 /k/key && chown 1001:1001 /k/key'
	@echo "key stored. it takes effect on the next: make update C=aiagent"

# A one-off in the foreground, so it neither rebuilds the image nor disturbs the
# aiagent container. Weights it pulls stay in the volume.
serve:
	@test -n "$(MODEL)" || { \
		echo "usage: make serve MODEL=<hf-repo>:<quant>" >&2; \
		exit 1; \
	}
	$(DOCKER) run --rm --gpus all --volume bythewood-models:/models \
		$(REGISTRY)/aiagent:latest -hf $(MODEL) --alias local

require-container:
	@test -d "containers/$(C)" || { \
		echo "there is no container called '$(C)'. one of:" >&2; \
		echo "  webdev" >&2; \
		echo "  aiagent" >&2; \
		exit 1; \
	}

require-webdev:
	@$(DOCKER) inspect --format '{{.State.Running}}' $(WEBDEV) 2>/dev/null | grep -q true || { \
		echo "$(WEBDEV) is not running, and this target works inside it." >&2; \
		echo "start it with: make up" >&2; \
		exit 1; \
	}
