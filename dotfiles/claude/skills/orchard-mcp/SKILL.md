---
name: orchard-mcp
description: Sign Claude Code on this box into the orchard MCP connector at mcp.bythewood.me, or sign it in again. Invoke when the orchard MCP server shows "Needs authentication" or fails with a 401, when Isaac says to connect or reconnect orchard or mcp, or when mcp.bythewood.me says nothing is connected. Isaac only has to read a six digit code off his phone.
---

# Signing in to orchard's MCP connector

The orchard server is added at user scope (`claude mcp add --scope user --transport http orchard https://mcp.bythewood.me/mcp`) and its token lives in `~/.claude/.credentials.json` under `mcpOAuth`. Both are on the `claude-home` volume so they survive a container rebuild. The grant is a 90 day auth session and Claude Code refreshes the hourly access token on its own, so this should only be needed about every 90 days or after Isaac revokes "Claude (connector)" on auth.bythewood.me/sessions.

Check first with `claude mcp list | grep orchard`. If it says Connected there's nothing to do. If the server is missing, add it with the command above.

## Steps

Do this in the scratchpad so playwright-cli's state lands there.

1. `~/.claude/skills/orchard-mcp/start-login.sh <scratchpad>` prints the authorize URL. The login gives up after 5 minutes, so don't start it until you're ready to go.
2. `playwright-cli open "<url>"` then `playwright-cli snapshot`. If auth's sign in in this browser is still fresh it lands straight on "Let Claude Code read orchard?" and you can skip to step 4.
3. Otherwise it's on auth's login page. Fill the Username box with `isaac` and click "Send a code". A code goes to ntfy on his phone and says it came from the VPS. Ask Isaac for it in one line, then click the "Digit 1" box and `playwright-cli type <code>`, which signs in and carries on to the connect page. Don't close the browser between the code and Allow, since the session cookie dies with it.
4. Click "Allow read access". auth shows "Handing you back to mcp.bythewood.me" and a meta refresh goes on through mcp to the localhost callback.
5. `tail -3 <scratchpad>/login.log` should say `Authenticated with "orchard"`, and `claude mcp list` should say Connected. Then `playwright-cli close`. The tools load in the next session and not this one.

If the 5 minutes ran out while waiting on Isaac, run step 1 again and reuse the same browser, since a code he already gave keeps the browser signed in for a while and he won't need to send another.

## What will bite

- Don't `pkill -f` the login with a pattern, since the pattern is also in your own shell's command line and it kills your Bash call (exit 144).
- auth's CSP has `form-action 'self'` and Chrome applies it to a form's redirects, which is why `/connect` hands back with a meta refresh and not a 303. If Allow ever stalls on the connect page again, `playwright-cli console` shows the CSP error.
- Only the two claude.ai client metadata documents can start a sign in, and Claude Code's redirect is `http://localhost/callback` on any port.
