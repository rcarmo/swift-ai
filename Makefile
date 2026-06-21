.PHONY: static-check test validate clean

static-check:
	python3 scripts/static-check.py

test:
	swift test

validate: static-check test

clean:
	rm -rf .build .swiftpm
