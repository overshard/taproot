#!/bin/sh
# Use the shared model gateway when there is one, and be a model server when
# there is not.
#
# llm.bythewood.me holds one set of weights on one card for the whole estate, so
# on the desktop this container should not load a second copy and evict it. On a
# laptop, or with the gateway down, there is no gateway to use and the container
# has to be the thing that serves the model, which is what it always was.
#
# The choice is made once at start, and which way it went is printed, because a
# container that quietly loaded 6GB of weights it did not need looks identical
# to one that did the right thing.
set -eu

GATEWAY="${LLM_URL:-https://llm.bythewood.me}"
MODELS_JSON="${HOME:-/home/ai}/.pi/agent/models.json"

# The key lives in a volume so replacing the container does not lose it, the
# same way the restic credentials do. An environment variable wins, which is
# what a one-off `docker run` uses.
KEY_FILE="${HOME:-/home/ai}/.llm/key"
KEY="${LLM_KEY:-}"
if [ -z "$KEY" ] && [ -r "$KEY_FILE" ]; then
	KEY=$(tr -d " \t\r\n" < "$KEY_FILE")
fi

# A key is required, so a machine with no key falls through to its own model
# rather than sitting there getting 401s from a gateway it cannot use.
gateway_answers() {
	[ -n "$KEY" ] || return 1
	curl -fsS --max-time 5 \
		-H "Authorization: Bearer $KEY" \
		"$GATEWAY/v1/models" >/dev/null 2>&1
}

point_pi_at() {
	tmp="$MODELS_JSON.tmp"
	jq --arg url "$1/v1" --arg key "$2" \
		'.providers.local.baseUrl = $url | .providers.local.apiKey = $key' \
		"$MODELS_JSON" > "$tmp" && mv "$tmp" "$MODELS_JSON"
}

if gateway_answers; then
	point_pi_at "$GATEWAY" "$KEY"
	echo "using the model gateway at $GATEWAY, no weights loaded here" >&2
	# Nothing to serve, but the container is a place to exec into, so it has
	# to stay up. It runs with --init, which reaps what tmux leaves behind.
	exec sleep infinity
fi

if [ -n "$KEY" ]; then
	echo "the gateway at $GATEWAY did not answer, serving a model here instead" >&2
else
	echo "no LLM_KEY set, serving a model here" >&2
fi
point_pi_at "http://127.0.0.1:8000" "none"
exec /usr/local/bin/llama-server "$@"
