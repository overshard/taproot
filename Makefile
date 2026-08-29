# taproot
#
# Three commands cover both containers:
#
#   make up          create what is missing and start it; safe to re-run
#   make update      rebuild the image and replace the running container
#   make doctor      what exists, what is running, what to type
#
# Both take C= to pick a container. It defaults to webdev, which is the one you
# live in:
#
#   make up C=aiagent
#   make update C=aiagent
#
# And the rest:
#
#   make shell       attach via tmux
#   make stop        stop it without replacing anything
#   make models      fetch the model weights once; needs the network
#
# Run from a clone of this repo, which is the build context.
#
# The docker socket is root-owned, so every command goes through sudo. On a host
# where docker needs no sudo (Docker Desktop), turn it off:  make up SUDO=

SUDO   ?= sudo
DOCKER ?= $(SUDO) docker

C ?= webdev
REGISTRY ?= overshard

VOLUMES = bythewood-code bythewood-claude bythewood-ssh bythewood-restic bythewood-models

NAME  = bythewood-$(C)
IMAGE = $(REGISTRY)/$(C):latest

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
	--volume /var/run/docker.sock:/var/run/docker.sock

RUN_ARGS = $(RUN_$(C))

.DEFAULT_GOAL := help
.PHONY: help up update doctor shell stop models dotfiles require-container

help:
	@echo "make up             create what is missing and start it; safe to re-run"
	@echo "make update         rebuild the image and replace the running container"
	@echo "make doctor         what exists, what is running, what to type"
	@echo ""
	@echo "make shell          attach via tmux"
	@echo "make stop           stop it, without replacing anything"
	@echo "make models         fetch the model weights once; needs the network"
	@echo ""
	@echo "add C=aiagent to any of the above. it defaults to webdev."
	@echo ""
	@echo "a machine that has never run this: make up, then follow what doctor says"

# ---------------------------------------------------------------- the system

# Idempotent, and the repair command as much as the first-run command. Creates
# the volumes, builds the image if it is not there, creates the container if it
# is not there, starts it if it is stopped, and leaves it alone if it is fine.
# It never replaces a running container; that is `update`.
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

# Rebuild, then replace. The build happens first and does not touch the running
# container, so only the last couple of seconds are disruptive.
#
# Replacing webdev FROM INSIDE webdev cannot be done directly: `docker rm
# --force` on your own container kills the make process doing the removing, so
# the `docker run` that should follow never happens and you are left with no
# container at all. A throwaway docker:cli does the swap instead. It is a
# separate container, so webdev dying does not take it with it, and it runs as
# root, so it needs no sudo of its own.
#
# Nothing below may contain $$(MAKE). GNU make runs any recipe line carrying
# that string even under `-n`, and because the whole swap is one shell
# conditional, a single `$$(MAKE) doctor` tacked on the end turned `make -n
# update` into a real container replacement. Ask for doctor by name instead.
update: require-container
	$(DOCKER) build --tag $(IMAGE) -f containers/$(C)/Dockerfile .
	@self=$$(cat /etc/hostname 2>/dev/null); \
	target=$$($(DOCKER) inspect --format '{{.Id}}' $(NAME) 2>/dev/null | cut -c1-12); \
	if [ -n "$$target" ] && [ "$$self" = "$$target" ]; then \
		echo ""; \
		echo "replacing the container you are sitting in."; \
		echo "this shell will drop in about two seconds. to get back in:"; \
		echo ""; \
		echo "    docker exec -it $(NAME) tmux"; \
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

# Read only. Every line is either fine or carries the command that fixes it.
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
	if $(DOCKER) exec bythewood-webdev test -s /home/dev/.ssh/home_key 2>/dev/null; then \
		echo "  git ssh key     ok"; \
	else \
		echo "  git ssh key     MISSING  -> docker cp \$$HOME/.ssh/home_key bythewood-webdev:/home/dev/.ssh/home_key"; \
	fi; \
	$(DOCKER) exec bythewood-webdev restic-setup --check >/dev/null 2>&1; \
	case $$? in \
	0)   echo "  restic          ok" ;; \
	127) echo "  restic          unknown  -> image predates restic-setup, run: make update" ;; \
	*)   echo "  restic          NOT SET UP  -> docker exec -it bythewood-webdev restic-setup" ;; \
	esac; \
	if $(DOCKER) exec bythewood-webdev test -L /home/dev/.claude/skills 2>/dev/null; then \
		echo "  claude dotfiles ok"; \
	else \
		echo "  claude dotfiles MISSING  -> make dotfiles"; \
	fi

shell: require-container
	$(DOCKER) exec -it $(NAME) tmux

stop: require-container
	$(DOCKER) stop $(NAME)

# /home/dev/.claude is a volume and shadows whatever the image puts there, so
# these have to be linked into the running container. Safe to re-run.
dotfiles:
	$(DOCKER) exec bythewood-webdev sh -c \
		"ln -snf /home/dev/code/taproot/dotfiles/claude/skills /home/dev/.claude/skills && \
		 ln -snf /home/dev/code/taproot/dotfiles/claude/status-line.sh /home/dev/.claude/status-line.sh"
	echo "claude skills and status line linked"

# The only step that reaches Hugging Face; weights land in the volume. Starts
# the server with offline disabled, waits for it to come up, then tears it
# down. --list-devices does not work here: it exits before -hf is resolved.
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

require-container:
	@test -d "containers/$(C)" || { \
		echo "there is no container called '$(C)'. one of:" >&2; \
		echo "  webdev" >&2; \
		echo "  aiagent" >&2; \
		exit 1; \
	}
