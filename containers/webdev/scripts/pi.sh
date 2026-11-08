#!/bin/sh
#
# pi, with Ornith served in this container for as long as any pi is open.
#
# The card fits one copy of the model and orchard's llm gateway wants it too,
# so the first pi starts llama-server and the last one to exit stops it. In
# between --sleep-idle-seconds drops the model after three idle minutes, the
# same as the gateway's ttl, so a pi left open doesn't sit on the card.
#
# Every open pi holds a shared flock on $LOCK, so the one that can turn its
# lock exclusive on the way out is the last one. $LOCK.start keeps two pis
# from starting a server each.

set -eu

PI=/usr/local/bin/pi
MODEL=/models/ornith/Ornith-1.5-9B-heretic-Q4_K_M.gguf
# The abliterated GGUF ships the plain upstream template, which raises on a
# system message anywhere but first, so the stock one rides beside it.
TEMPLATE=/usr/local/share/ornith/chat-template.jinja
PORT=8080
LOG="$HOME/.cache/ornith.log"
LOCK=/tmp/ornith.lock

# Ornith at 64k measured 7307MiB of the 8GB card with an idle desktop beside
# it, so anything much under this is a game or the gateway's own copy.
NEED_MIB=6500

start() {
	if [ ! -s "$MODEL" ]; then
		echo "pi: no weights at $MODEL. from a taproot clone: make models" >&2
		exit 1
	fi
	if ! free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1) || [ -z "$free" ]; then
		echo "pi: no GPU in this container. a Windows driver update does this, and" >&2
		echo "pi: replacing the container fixes it. from a taproot clone: make update" >&2
		exit 1
	fi
	if [ "$free" -lt "$NEED_MIB" ]; then
		echo "pi: only ${free}MiB free on the card and Ornith needs about ${NEED_MIB}MiB." >&2
		echo "pi: orchard's llm gateway lets go of its copy 3 minutes after its last" >&2
		echo "pi: call, and a game holds the card until it closes. try again after." >&2
		exit 1
	fi

	mkdir -p "$(dirname "$LOG")"
	echo "pi: loading Ornith, log in $LOG" >&2
	# Closing 8 and 9 for it, or the server holds the locks after every pi is gone.
	setsid llama-server \
		-m "$MODEL" \
		--alias local \
		--host 127.0.0.1 --port "$PORT" \
		--ctx-size 65536 \
		--n-gpu-layers 999 \
		--flash-attn on \
		--cache-type-k q4_0 --cache-type-v q4_0 \
		--parallel 1 \
		--batch-size 2048 --ubatch-size 256 \
		--jinja \
		--chat-template-file "$TEMPLATE" \
		--reasoning off \
		--temp 0.7 --top-p 0.8 --top-k 20 \
		--sleep-idle-seconds 180 \
		</dev/null >"$LOG" 2>&1 8>&- 9>&- &

	i=0
	until curl -fs -o /dev/null "http://127.0.0.1:$PORT/health"; do
		if ! pgrep -x llama-server >/dev/null || [ "$i" -ge 120 ]; then
			echo "pi: llama-server did not come up, the end of its log:" >&2
			tail -n 20 "$LOG" >&2
			pkill -x llama-server || true
			exit 1
		fi
		i=$((i + 1))
		sleep 1
	done
}

# Waits for the server to be gone so the next pi doesn't find it mid exit and
# think there's nothing to start.
stop() {
	flock -xn 9 || return 0
	pkill -x llama-server || return 0
	i=0
	while pgrep -x llama-server >/dev/null; do
		[ "$i" -lt 10 ] || pkill -KILL -x llama-server || true
		i=$((i + 1))
		sleep 1
	done
}

# pi's own subcommands and help never call the model, so there's nothing to load.
case "${1:-}" in
install|remove|uninstall|update|list|config|auth|mcp|-h|--help|-v|--version)
	exec "$PI" "$@" ;;
esac

exec 9>"$LOCK"
flock -s 9
exec 8>"$LOCK.start"
flock -x 8
pgrep -x llama-server >/dev/null || start
exec 8>&-

trap stop EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

"$PI" "$@" 9>&-
