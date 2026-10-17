NVIM ?= nvim
DEPS := deps

.PHONY: test deps clean

test: deps
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run one file: make test-file FILE=tests/test_store.lua
test-file: deps
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

deps: $(DEPS)/mini.nvim

$(DEPS)/mini.nvim:
	@mkdir -p $(DEPS)
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $@

clean:
	rm -rf $(DEPS)
