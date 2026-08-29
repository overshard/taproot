# Build and run the containers, and link the dotfiles that cannot be baked in.
# Run from a clone of this repo, which is the build context.
#
# The docker socket is root-owned, so DOCKER defaults to sudo. On a host where
# docker needs no sudo (Docker Desktop), override it: make build DOCKER=docker

DOCKER ?= sudo docker
REGISTRY ?= overshard
VOLUMES = bythewood-code bythewood-claude bythewood-ssh bythewood-restic bythewood-ai-models

WEBDEV_RUN = --detach --name bythewood-webdev --init --restart unless-stopped \
	--publish 8000:8000 \
	--volume bythewood-code:/home/dev/code \
	--volume bythewood-claude:/home/dev/.claude \
	--volume bythewood-ssh:/home/dev/.ssh \
	--volume bythewood-restic:/home/dev/.restic \
	--volume /var/run/docker.sock:/var/run/docker.sock

AIAGENT_RUN = --detach --name bythewood-aiagent --init --gpus all \
	--volume bythewood-code:/home/ai/code \
	--volume bythewood-ssh:/home/ai/.ssh \
	--volume bythewood-ai-models:/models \
	--volume /var/run/docker.sock:/var/run/docker.sock

.DEFAULT_GOAL := help
.PHONY: help volumes build webdev aiagent swap-webdev swap-aiagent \
	shell-webdev shell-aiagent stop-aiagent models dotfiles push

help:
	@echo "volumes        create the named volumes that hold everything"
	@echo "build          build both images"
	@echo "webdev         build the webdev image"
	@echo "aiagent        build the aiagent image"
	@echo "swap-webdev    replace the running webdev container with the built image"
	@echo "swap-aiagent   replace the running aiagent container with the built image"
	@echo "shell-webdev   attach to webdev via tmux"
	@echo "shell-aiagent  attach to aiagent via tmux"
	@echo "stop-aiagent   stop the model server and free the VRAM"
	@echo "models         fetch the weights once (needs network)"
	@echo "dotfiles       link claude skills and status line into the volume"
	@echo "push           push main to every remote"

volumes:
	@for v in $(VOLUMES); do $(DOCKER) volume create $$v >/dev/null; done
	@echo "volumes ready: $(VOLUMES)"

build: webdev aiagent

webdev:
	$(DOCKER) build --tag $(REGISTRY)/webdev:latest -f containers/webdev/Dockerfile .

aiagent:
	$(DOCKER) build --tag $(REGISTRY)/aiagent:latest -f containers/aiagent/Dockerfile .

# Recreating drops the running tmux session. Volumes are untouched.
swap-webdev:
	-$(DOCKER) rm --force bythewood-webdev
	$(DOCKER) run $(WEBDEV_RUN) $(REGISTRY)/webdev:latest

swap-aiagent:
	-$(DOCKER) rm --force bythewood-aiagent
	$(DOCKER) run $(AIAGENT_RUN) $(REGISTRY)/aiagent:latest

shell-webdev:
	$(DOCKER) exec -it bythewood-webdev tmux

shell-aiagent:
	$(DOCKER) exec -it bythewood-aiagent tmux

stop-aiagent:
	$(DOCKER) stop bythewood-aiagent

# The only step that reaches Hugging Face; weights land in the volume. Starts
# the server with offline disabled, waits for it to come up, then tears it
# down. --list-devices does not work here: it exits before -hf is resolved.
models:
	-$(DOCKER) rm --force aiagent-fetch
	$(DOCKER) run --detach --name aiagent-fetch --gpus all \
		--env LLAMA_ARG_OFFLINE=false \
		--volume bythewood-ai-models:/models $(REGISTRY)/aiagent:latest
	@echo "downloading weights, several GB, this takes a while"
	@while ! $(DOCKER) exec aiagent-fetch curl -sf -o /dev/null http://127.0.0.1:8000/health 2>/dev/null; do \
		$(DOCKER) ps -q -f name=aiagent-fetch | grep -q . || \
			{ echo "fetch failed:"; $(DOCKER) logs --tail 20 aiagent-fetch; exit 1; }; \
		sleep 10; \
	done
	@$(DOCKER) rm --force aiagent-fetch >/dev/null
	@echo "weights are in the bythewood-ai-models volume"

# /home/dev/.claude is a volume and shadows whatever the image puts there, so
# these have to be linked into the running container. Safe to re-run.
dotfiles:
	$(DOCKER) exec bythewood-webdev sh -c \
		"ln -snf /home/dev/code/taproot/dotfiles/claude/skills /home/dev/.claude/skills && \
		 ln -snf /home/dev/code/taproot/dotfiles/claude/status-line.sh /home/dev/.claude/status-line.sh"
	@echo "claude skills and status line linked"

push:
	git remote | xargs -I R git push R main
