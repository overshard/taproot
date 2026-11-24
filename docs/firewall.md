# The Docker firewall guard

Docker writes its own iptables rules for a published port and they're checked
before ufw's, so `ports: "8080:8000"` in any compose file is open to the
internet whatever `ufw status` says. Only 853 is meant to be published here.
Docker leaves one chain alone for this, `DOCKER-USER`, which every packet
headed for a container passes first.

This goes at the end of `/etc/ufw/after.rules`, after the `COMMIT` that's
already there, with `PUBLIC_IF` swapped for the public interface that
`ip route show default` names after `dev`:

```
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i PUBLIC_IF -p tcp -m conntrack --ctorigdstport 853 -j RETURN
-A DOCKER-USER -i PUBLIC_IF -j DROP
COMMIT
```

Then `sudo ufw reload`. The first rule lets replies back in to connections a
container opened, the second lets new connections to 853 through, and the third
drops anything else arriving from the internet for a container. It matches on
the port the client dialled since Docker has already rewritten it to 8853 by
this point. Nothing here touches traffic to the host itself, so ssh and
WireGuard can't be locked out by it.

To check it, `sudo iptables -S DOCKER-USER` should list the three rules once,
DNS over TLS should still answer on a phone, and the sites should still load
and still reach the outside (dash's markets are a quick tell).

To undo it, delete the block from `/etc/ufw/after.rules`, then
`sudo iptables -F DOCKER-USER && sudo ufw reload`.

To publish another port later, add a line like the 853 one above the `DROP`.
