PROJECT_NAME := swift-ai
SWIFT ?= swift
PROJECT_TMP_RESOLVER := $(CURDIR)/scripts/project_tmp.py
PROJECT_TMP_ROOT_ORIGIN := $(origin PROJECT_TMP_ROOT)
PROJECT_TMP_ROOT_INPUT := $(value PROJECT_TMP_ROOT)
PROJECT_TMP_BASE_ORIGIN := $(origin PROJECT_TMP_BASE)
PROJECT_TMP_BASE_INPUT := $(value PROJECT_TMP_BASE)
export PROJECT_ORIGINAL_TMPDIR := $(TMPDIR)
override PROJECT_TMP_ROOT := $(shell python3 '$(PROJECT_TMP_RESOLVER)' root $(if $(filter undefined,$(PROJECT_TMP_ROOT_ORIGIN)),,--root '$(PROJECT_TMP_ROOT_INPUT)') $(if $(filter undefined,$(PROJECT_TMP_BASE_ORIGIN)),,--base '$(PROJECT_TMP_BASE_INPUT)'))
ifeq ($(strip $(PROJECT_TMP_ROOT)),)
$(error Could not resolve PROJECT_TMP_ROOT for $(PROJECT_NAME))
endif
SWIFT_AI_TMP_ROOT := $(PROJECT_TMP_ROOT)
CACHE_ROOT := $(SWIFT_AI_TMP_ROOT)/cache
BUILD_ROOT := $(SWIFT_AI_TMP_ROOT)/build
TEST_ROOT := $(SWIFT_AI_TMP_ROOT)/tests
LOG_ROOT := $(SWIFT_AI_TMP_ROOT)/logs
RUN_ROOT := $(SWIFT_AI_TMP_ROOT)/runs
RUN_PURPOSE ?= make
ifndef RUN_ID
RUN_ID := $(shell date -u +%Y%m%dT%H%M%S)-$(shell date +%s%N)
endif
RUN_DIR := $(RUN_ROOT)/$(RUN_PURPOSE)/$(RUN_ID)
RUN_TMP := $(RUN_DIR)/tmp
SWIFTPM_BUILD_ROOT := $(BUILD_ROOT)/swiftpm
SWIFTPM_CACHE_ROOT := $(CACHE_ROOT)/swiftpm
SWIFTPM_CONFIG_ROOT := $(CACHE_ROOT)/swiftpm-config
SWIFTPM_SECURITY_ROOT := $(CACHE_ROOT)/swiftpm-security
SWIFT_MODULE_CACHE_ROOT := $(CACHE_ROOT)/swift-module

export SWIFT PROJECT_TMP_ROOT PROJECT_ORIGINAL_TMPDIR SWIFT_AI_TMP_ROOT CACHE_ROOT BUILD_ROOT TEST_ROOT LOG_ROOT RUN_ROOT RUN_DIR
export SWIFT_AI_RUN_TMP := $(RUN_TMP)
export SWIFT_AI_TEST_RUN_ROOT := $(RUN_DIR)/test-fs
export TMPDIR := $(RUN_TMP)
export TMP := $(RUN_TMP)
export TEMP := $(RUN_TMP)
export CLANG_MODULE_CACHE_PATH := $(SWIFT_MODULE_CACHE_ROOT)
export SWIFTPM_MODULECACHE_OVERRIDE := $(SWIFT_MODULE_CACHE_ROOT)
export PYTHONPYCACHEPREFIX := $(CACHE_ROOT)/python/pycache
export XDG_CACHE_HOME := $(CACHE_ROOT)/xdg
export XDG_CONFIG_HOME := $(CACHE_ROOT)/xdg-config
export GOCACHE := $(CACHE_ROOT)/go-build
export GOMODCACHE := $(CACHE_ROOT)/go-mod
export GOPATH := $(CACHE_ROOT)/go-path
export SWIFT_AI_SWIFTPM_SCRATCH := $(SWIFTPM_BUILD_ROOT)
export SWIFT_AI_SWIFTPM_CACHE := $(SWIFTPM_CACHE_ROOT)
export SWIFT_AI_SWIFTPM_CONFIG := $(SWIFTPM_CONFIG_ROOT)
export SWIFT_AI_SWIFTPM_SECURITY := $(SWIFTPM_SECURITY_ROOT)
export SWIFT_AI_OSV_CACHE := $(CACHE_ROOT)/osv-scanner

SWIFT_PACKAGE_FLAGS = --scratch-path $(SWIFTPM_BUILD_ROOT) --cache-path $(SWIFTPM_CACHE_ROOT) --config-path $(SWIFTPM_CONFIG_ROOT) --security-path $(SWIFTPM_SECURITY_ROOT)
SWIFT_COMPILER_CACHE_FLAGS = -Xswiftc -module-cache-path -Xswiftc $(SWIFT_MODULE_CACHE_ROOT)

.PHONY: tmp-paths tmp-init static-check build test sbom sbom-check sbom-scan check validate clean
.NOTPARALLEL: check validate

tmp-paths:
	@printf '%s\n' \
		"SWIFT_AI_TMP_ROOT=$(SWIFT_AI_TMP_ROOT)" \
		"CACHE_ROOT=$(CACHE_ROOT)" \
		"BUILD_ROOT=$(BUILD_ROOT)" \
		"TEST_ROOT=$(TEST_ROOT)" \
		"LOG_ROOT=$(LOG_ROOT)" \
		"RUN_DIR=$(RUN_DIR)"

tmp-init: tmp-paths
	@set -eu; root='$(SWIFT_AI_TMP_ROOT)'; purpose='$(RUN_PURPOSE)'; run_id='$(RUN_ID)'; \
	case "$$purpose" in ''|*[!A-Za-z0-9._-]*|.*|-*) echo 'RUN_PURPOSE must be a safe path component' >&2; exit 1;; esac; \
	case "$$run_id" in ''|*[!A-Za-z0-9._-]*|.*|-*) echo 'RUN_ID must be a safe path component' >&2; exit 1;; esac; \
	resolved="$$(python3 '$(PROJECT_TMP_RESOLVER)' root --root "$$root")"; test "$$resolved" = "$$root" || { echo 'resolved project root changed unexpectedly' >&2; exit 1; }; \
	for path in "$$root" '$(CACHE_ROOT)' '$(BUILD_ROOT)' '$(TEST_ROOT)' '$(LOG_ROOT)' '$(RUN_ROOT)' '$(RUN_DIR)' '$(RUN_TMP)' '$(SWIFT_AI_TEST_RUN_ROOT)'; do \
		test ! -L "$$path" || { echo "Refusing symlink cache/temp path: $$path" >&2; exit 1; }; \
		if test -e "$$path"; then test -d "$$path" && test -O "$$path" || { echo "Cache/temp path must be an owned directory: $$path" >&2; exit 1; }; fi; \
	done; \
	mkdir -p '$(SWIFTPM_BUILD_ROOT)' '$(SWIFTPM_CACHE_ROOT)' '$(SWIFTPM_CONFIG_ROOT)' '$(SWIFTPM_SECURITY_ROOT)' '$(SWIFT_MODULE_CACHE_ROOT)' '$(PYTHONPYCACHEPREFIX)' '$(XDG_CACHE_HOME)' '$(XDG_CONFIG_HOME)' '$(GOCACHE)' '$(GOMODCACHE)' '$(GOPATH)' '$(SWIFT_AI_OSV_CACHE)' '$(TEST_ROOT)' '$(LOG_ROOT)' '$(RUN_TMP)' '$(SWIFT_AI_TEST_RUN_ROOT)'

static-check: tmp-init
	python3 scripts/test-project-tmp.py
	python3 scripts/static-check.py

build: tmp-init
	$(SWIFT) build $(SWIFT_PACKAGE_FLAGS) $(SWIFT_COMPILER_CACHE_FLAGS) -Xswiftc -warnings-as-errors

test: tmp-init
	$(SWIFT) test $(SWIFT_PACKAGE_FLAGS) $(SWIFT_COMPILER_CACHE_FLAGS)

sbom: tmp-init
	python3 scripts/sbom.py generate

sbom-check: sbom
	python3 scripts/sbom.py check
	python3 scripts/sbom.py scan

sbom-scan: sbom-check

check: static-check sbom-check build test

validate: check

clean:
	@set -eu; root='$(SWIFT_AI_TMP_ROOT)'; \
	resolved="$$(python3 '$(PROJECT_TMP_RESOLVER)' root --root "$$root")"; test "$$resolved" = "$$root" || { echo 'Refusing unsafe cleanup root' >&2; exit 1; }; \
	for path in '$(CACHE_ROOT)' '$(BUILD_ROOT)'; do \
		test ! -L "$$path" || { echo "Refusing symlink cleanup path: $$path" >&2; exit 1; }; \
		case "$$path" in "$$root"/cache|"$$root"/build) rm -rf -- "$$path";; *) echo "Refusing cleanup outside $$root: $$path" >&2; exit 1;; esac; \
	done
