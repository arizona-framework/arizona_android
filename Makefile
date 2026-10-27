# The arizona this client is built and tested against: the release tag pinned in
# .arizona-version, cloned into _arizona by `make arizona`. Point ARIZONA_DIR at
# another checkout (e.g. ../arizona) to try a client change against unreleased
# arizona code; CI always uses the pin.
ARIZONA_VERSION := $(shell cat .arizona-version)
ARIZONA_DIR ?= _arizona

.PHONY: arizona build test check-wire server e2e

# Debug APK of the sample app.
build:
	gradle :sample:assembleDebug

# Wire-protocol logic tests (pure JVM; no emulator, no server).
test:
	gradle :arizona:testDebugUnitTest

# Op/effect codes in Wire.kt against the arizona headers. Needs a compiled
# checkout (`rebar3 compile` there, or a `make server` run).
check-wire:
	scripts/check_wire.escript $(ARIZONA_DIR)

# Clone the pinned arizona release and install its JS deps (the e2e server
# builds the Vite bundle).
arizona:
	git clone --quiet --depth 1 --branch $(ARIZONA_VERSION) https://github.com/arizona-framework/arizona.git _arizona
	cd _arizona && npm ci

# Arizona's e2e test server on :4040, which serves the /native examples.
server:
	cd $(ARIZONA_DIR) && PORT=4040 ERLANG_EXTRA_ARGS=-noshell ./scripts/start_test_server.sh

# Compose UI tests on a running emulator/device against `make server`. The
# :sample build's adbReverse task tunnels localhost:4040 first.
e2e:
	gradle :sample:connectedCheck
