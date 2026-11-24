#!/bin/sh
#
# guard-bash.sh
#
# A PreToolUse hook for Bash. This container holds the host's Docker socket, so
# one docker run with the wrong flags is root on the VPS. It refuses the shapes
# that turn the socket into the host, and nsenter and curl piped into a shell.
# It only reads the command typed, so the same flags in a script get past it,
# and ~/scripts/on-host is the one script meant to, for work on the host.
# Exit 2 blocks the call and hands the reason back to Claude.

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# One line, no quotes and no line continuations, so "-v '/:/host'" and a flag
# on the next line still match.
flat=$(printf '%s' "$cmd" | sed -e ':a' -e 'N' -e '$!ba' -e 's/\\\n/ /g' | tr '\n\t' '  ' | tr -d "\"'")

deny() {
    echo "guard-bash: refused, $1. This box's Docker socket is root on the host, so ask Isaac to run it by hand if it's really needed." >&2
    exit 2
}

if printf '%s' "$flat" | grep -Eq '(^|[^a-z])nsenter([^a-z]|$)'; then
    deny "nsenter enters the host's namespaces"
fi
if printf '%s' "$flat" | grep -Eq '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|da|z)?sh([^a-z]|$)'; then
    deny "piping a download into a shell"
fi

printf '%s' "$flat" | grep -Eq '(^|[^a-z])(docker|podman)([^a-z-]|$)' || exit 0

if printf '%s' "$flat" | grep -Eq -- '--privileged'; then
    deny "--privileged"
fi
if printf '%s' "$flat" | grep -Eq -- '--(pid|userns|ipc|uts)[= ]+host'; then
    deny "sharing a host namespace"
fi
if printf '%s' "$flat" | grep -Eiq -- '--cap-add[= ]+(cap_)?all([^a-z]|$)'; then
    deny "--cap-add=ALL"
fi
if printf '%s' "$flat" | grep -Eiq -- '--cap-add[= ]+(cap_)?(sys_|dac_|net_admin|bpf|perfmon|mknod)'; then
    deny "adding a capability that reaches the host"
fi
if printf '%s' "$flat" | grep -Eq -- '--device([= ]|-cgroup-rule)|--security-opt[= ]+[a-z-]*[=:]unconfined'; then
    deny "a host device or an unconfined profile"
fi
# The host's /etc may be mounted read only, to look at units and config.
flat=$(printf '%s' "$flat" | sed -E 's#(^| )(-v|--volume)(=| )/etc:/[A-Za-z0-9/_-]+:ro( |$)#\1\4#g')

# Only a named volume may be mounted from here. A path, a variable or the
# socket as the source is refused, however it's spelled.
if printf '%s' "$flat" | grep -Eq -- '(^| )(-v|--volume)(=| )?[^A-Za-z0-9 ][^ ]*:'; then
    deny "mounting anything but a named volume"
fi
if printf '%s' "$flat" | grep -Eq -- '--mount[= ][^ ]*(type=bind|(source|src)=[^A-Za-z0-9])'; then
    deny "mounting anything but a named volume"
fi
exit 0
