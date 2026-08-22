QMLLINT ?= /usr/lib/qt6/bin/qmllint

.PHONY: test test-js test-shell qml-check validate

test: test-js test-shell

test-js:
	@set -e; for file in tests/test_*.js; do [ -f "$$file" ] || continue; node "$$file"; done

test-shell:
	@set -e; for file in tests/test_*.sh; do [ -f "$$file" ] || continue; bash "$$file"; done

qml-check:
	@if [ -x "$(QMLLINT)" ]; then \
		files="$$(find . -type f -name '*.qml' -not -path './.git/*' -print)"; \
		if [ -n "$$files" ]; then set +e; $(QMLLINT) -I /usr/share/omarchy/shell $$files; rc=$$?; set -e; [ $$rc -le 1 ] || exit $$rc; fi; \
	else echo 'qmllint not installed; skipping QML lint'; fi

validate: test qml-check
	@if command -v omarchy >/dev/null 2>&1; then omarchy plugin validate .; else echo 'omarchy not installed; skipping plugin validation'; fi
	@git diff --check
