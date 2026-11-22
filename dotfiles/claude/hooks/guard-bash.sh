#!/bin/sh
#
# guard-bash.sh
#
# A PreToolUse hook for Bash. This container holds the host's Docker socket, so
# one docker run with the wrong flags is root on the VPS. It refuses the shapes
# that turn the socket into the host, and nsenter and curl piped into a shell.
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
if printf '%s' "$flat" | grep -Eq -- '(^| )(-v|--volume)(=| )?/((etc|root)(/[^ :]*)?)?:'; then
    deny "bind mounting /, /etc or /root"
fi
if printf '%s' "$flat" | grep -Eq -- '--mount[= ][^ ]*(source|src)=/((etc|root)(/[^, ]*)?)?(,| |$)'; then
    deny "bind mounting /, /etc or /root"
fi
exit 0
