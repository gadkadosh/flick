.PHONY: build test format format-check

SWIFT ?= swift
CLANG_FORMAT ?= xcrun clang-format
SWIFT_FILES := Package.swift Sources Tests
OBJC_FILES := $(wildcard Sources/SkyLightBridge/*.m Sources/SkyLightBridge/include/*.h)

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

format:
	$(SWIFT) format format --configuration .swift-format --in-place --recursive $(SWIFT_FILES)
	$(if $(OBJC_FILES),$(CLANG_FORMAT) --style=file -i $(OBJC_FILES))

format-check:
	$(SWIFT) format lint --configuration .swift-format --strict --recursive $(SWIFT_FILES)
	$(if $(OBJC_FILES),$(CLANG_FORMAT) --style=file --dry-run --Werror $(OBJC_FILES))
