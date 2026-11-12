SHELL_FILES := bin/kswitch bin/kwhere bin/kopen lib/common.sh install.sh \
               tests/run.sh tests/fixtures.sh tests/fakebin/kubectl tests/fakebin/k9s \
               demo/shell.sh demo/bin/k9s
ZSH_FILES   := kubeshelf.plugin.zsh demo/play.zsh $(wildcard completions/_*)

.PHONY: all lint test demo demo-gif

all: lint test

lint:
	@for f in $(SHELL_FILES); do bash -n "$$f" || exit 1; done
	@for f in $(ZSH_FILES); do zsh -n "$$f" || exit 1; done
	@if command -v shellcheck >/dev/null; then \
		shellcheck $(SHELL_FILES) && echo "shellcheck: ok"; \
	else \
		echo "shellcheck not installed: syntax checks only (sudo apt install shellcheck)"; \
	fi

test:
	@tests/run.sh

# Record demo/demo.cast with asciinema (scripted session, fake clusters), then demo/demo.gif with agg
demo:
	@command -v asciinema >/dev/null || { echo "asciinema is required: sudo apt install asciinema"; exit 1; }
	asciinema rec --overwrite --cols 100 --rows 26 --idle-time-limit 3 \
		--title "kubeshelf demo" -c "zsh demo/play.zsh" demo/demo.cast
	@$(MAKE) --no-print-directory demo-gif

# Convert the existing demo/demo.cast to demo/demo.gif (no re-recording)
demo-gif:
	@command -v agg >/dev/null || { echo "agg is required to make demo/demo.gif: https://github.com/asciinema/agg"; exit 1; }
	agg --font-size 18 demo/demo.cast demo/demo.gif
	cp demo/demo.cast docs/demo.cast   # played by the GitHub Pages player (docs/index.html)
	@echo "demo/demo.gif and docs/demo.cast written"
