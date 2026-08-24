#!/bin/sh
# Cloudflare side of the tunnel test.
#
# There is no cloudflared binary here, so every step runs the official image.
# All tunnel state (cert.pem, the credentials JSON, the live config.yml) lives
# in the named volume tunnel-test-cloudflared, which is also what the compose
# stack mounts read-only. Nothing secret ever lands in the repo or on a host
# path, and the stack stays runnable from inside the webdev container, whose
# filesystem the host daemon cannot see.
#
#   sh setup-tunnel.sh login    once, interactive, prints a URL to authorize
#   sh setup-tunnel.sh up       create the tunnel, seed config.yml, route DNS
#   sh setup-tunnel.sh status   what exists on the Cloudflare side right now
#   sh setup-tunnel.sh down     delete the tunnel (the CNAME stays)
#
# Set DOCKER="sudo docker" where the socket needs it (the webdev container).
set -eu

DOCKER="${DOCKER:-docker}"
IMAGE="cloudflare/cloudflared:latest"
VOLUME="${VOLUME:-tunnel-test-cloudflared}"
TUNNEL_NAME="${TUNNEL_NAME:-bythewood-test}"
TUNNEL_HOSTNAME="${TUNNEL_HOSTNAME:-test.bythewood.me}"

DIR="$(cd "$(dirname "$0")" && pwd)"

# cloudflared's image runs as nonroot with home /home/nonroot, so that is where
# it looks for cert.pem and where it writes <uuid>.json.
cfd() {
	$DOCKER run --rm \
		--volume "$VOLUME:/home/nonroot/.cloudflared" \
		"$IMAGE" "$@"
}

# The cloudflared image is distroless, so it has no shell to poke at the volume
# with. Use a plain alpine for anything that needs one.
HELPER="${HELPER:-alpine:latest}"

in_volume() {
	$DOCKER run --rm \
		--volume "$VOLUME:/state" \
		"$HELPER" sh -c "$1"
}

# A fresh named volume is root-owned, and cloudflared runs as uid 65532. Without
# this it authenticates fine and then dies writing cert.pem with EACCES.
ensure_volume() {
	$DOCKER volume create "$VOLUME" >/dev/null
	in_volume 'chown -R 65532:65532 /state'
}

case "${1:-}" in
login)
	ensure_volume
	if in_volume 'test -f /state/cert.pem'; then
		echo "cert.pem already in $VOLUME, nothing to do"
		exit 0
	fi
	echo "A URL prints below. Open it, pick the bythewood.me zone, authorize."
	# No --tty: this has to work from a non-interactive shell too. cloudflared
	# only prints a URL and polls the callback, it never reads stdin.
	$DOCKER run --rm --name tunnel-test-login \
		--volume "$VOLUME:/home/nonroot/.cloudflared" \
		"$IMAGE" tunnel login
	in_volume 'test -f /state/cert.pem' || { echo "no cert.pem was written" >&2; exit 1; }
	echo "cert.pem is in $VOLUME"
	;;

up)
	ensure_volume
	in_volume 'test -f /state/cert.pem' \
		|| { echo "run 'sh setup-tunnel.sh login' first" >&2; exit 1; }

	if cfd tunnel list --name "$TUNNEL_NAME" 2>/dev/null | grep -q "$TUNNEL_NAME"; then
		echo "tunnel $TUNNEL_NAME already exists"
	else
		echo "creating tunnel $TUNNEL_NAME"
		cfd tunnel create "$TUNNEL_NAME"
	fi

	id="$(cfd tunnel list --name "$TUNNEL_NAME" --output json \
		| tr ',{' '\n\n' | grep '"id"' | head -1 | cut -d'"' -f4)"
	[ -n "$id" ] || { echo "could not read the tunnel id" >&2; exit 1; }
	echo "tunnel id $id"

	# Seed the repo's config.yml into the volume with the real id stamped in,
	# and put the credentials where config.yml says they are.
	# config.yml arrives on stdin, not as a bind mount: the host daemon cannot
	# see this container's filesystem, so a -v of a repo path would be empty.
	$DOCKER run --rm --interactive \
		--volume "$VOLUME:/state" \
		"$HELPER" sh -c "
			set -eu
			test -f /state/$id.json || { echo 'missing /state/$id.json' >&2; exit 1; }
			cp /state/$id.json /state/credentials.json
			sed 's|^tunnel: .*|tunnel: $id|' > /state/config.yml
			chown 65532:65532 /state/credentials.json /state/config.yml
			echo '--- config.yml now in the volume ---'
			cat /state/config.yml
		" < "$DIR/cloudflared/config.yml"

	echo "routing $TUNNEL_HOSTNAME to the tunnel (creates a proxied CNAME)"
	cfd tunnel route dns --overwrite-dns "$TUNNEL_NAME" "$TUNNEL_HOSTNAME"
	;;

status)
	cfd tunnel list || true
	echo "--- config.yml in $VOLUME ---"
	in_volume 'cat /state/config.yml 2>/dev/null || echo "(not seeded yet)"'
	;;

down)
	cfd tunnel cleanup "$TUNNEL_NAME" || true
	cfd tunnel delete "$TUNNEL_NAME"
	echo "tunnel deleted; the $TUNNEL_HOSTNAME CNAME is still in DNS, remove by hand"
	;;

*)
	sed -n '2,20p' "$0"
	exit 1
	;;
esac
