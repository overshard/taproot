# Dotfiles

Everything in `dotfiles/` is baked into the images at build time. `make dotfiles`
then links three of them back out of the checkout, the Claude skills and status
line because `/home/dev/.claude` is a volume and shadows whatever the image put
there, and the neovim config so that editing it takes effect in the container
you're already in instead of waiting on a rebuild.

Neovim has a file tree sidebar on `F2`, which opens it, and pressing it again
from a file jumps into it, and again from inside it closes it. `F3` reveals the
file you're in. It
is nvim-tree, cloned into `pack/dev/start/` by the Dockerfile so there is no
plugin manager and nothing to fetch on first run. The keys for wherever you are
run across the top of the screen while the tree is open, or along the statusline
when it is closed, and `?` inside the tree lists all of them. It shows dotfiles
and git ignored files, everything except the inside of `.git`, and `H` and `I`
put those two filters back.
