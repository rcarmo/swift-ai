.PHONY: static-check build test check validate clean

static-check:
	python3 scripts/static-check.py

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test

check: static-check build test

validate: check

clean:
	rm -rf .build .swiftpm
