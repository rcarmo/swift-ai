.PHONY: static-check build test sbom sbom-check sbom-scan check validate clean

static-check:
	python3 scripts/static-check.py

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test

sbom:
	python3 scripts/sbom.py generate

sbom-check: sbom
	python3 scripts/sbom.py check
	python3 scripts/sbom.py scan

sbom-scan: sbom-check

check: static-check sbom-check build test

validate: check

clean:
	rm -rf .build .swiftpm .artifacts
