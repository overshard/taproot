.PHONY: push

push:
	git remote | xargs -I R git push R main
