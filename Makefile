CLAUDE_CONFIG := $(HOME)/.claude/config.json

.PHONY: install

install:
	sudo find $(CURDIR) -user root -exec chown $$(id -un):$$(id -gn) {} +
	cd gitnexus_shared && npm install && cd ..
	cd gitnexus && npm install tsc && npm install && npm run build && sudo --preserve-env=PATH npm link
	mkdir -p $(HOME)/.claude
	test -f $(CLAUDE_CONFIG) || echo '{}' > $(CLAUDE_CONFIG)
	jq --argjson gitnexus '{"command":"/usr/bin/node","args":["$(CURDIR)/gitnexus/dist/cli/index.js","mcp"],"cwd":"/var/lib/gitnexus","env":{"NODE_ENV":"production"},"timeout":30000,"trust":false}' \
		'.mcpServers.gitnexus = $$gitnexus' $(CLAUDE_CONFIG) > $(CLAUDE_CONFIG).tmp && mv $(CLAUDE_CONFIG).tmp $(CLAUDE_CONFIG)
