DEST       ?= $(HOME)/.local/bin
CONFIG_DIR ?= $(HOME)/.config/ghupdate

.PHONY: install uninstall check test clean

# Put ghupdate on PATH and seed the config file if it does not exist.
# An existing config is never overwritten.
install:
	mkdir -p "$(DEST)"
	install -m 0755 ghupdate "$(DEST)/ghupdate"
	mkdir -p "$(CONFIG_DIR)"
	test -f "$(CONFIG_DIR)/config.json" || cp config.example.json "$(CONFIG_DIR)/config.json"
	@echo "ghupdate -> $(DEST)/ghupdate"

# Remove only the binary; config and state are kept.
uninstall:
	rm -f "$(DEST)/ghupdate"

# Offline sanity: python syntax + example config, no network.
check:
	python3 -m py_compile ghupdate
	python3 -c "import json; json.load(open('config.example.json'))"
	rm -rf __pycache__

# End-to-end: download and install the example tools (or a subset) into a
# temp directory, then run each binary.
#   make test                 # all tools
#   make test TOOLS=lazydocker
test:
	sh tests/run-test.sh $(TOOLS)

clean:
	rm -rf __pycache__
