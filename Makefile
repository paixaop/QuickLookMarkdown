SCHEME       = QuickMDApp
APP_NAME     = QuickMD
BUILD_BASE   = $(shell xcodebuild -scheme $(SCHEME) -configuration Release \
                 -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')
DIST_DIR     = dist
DMG_STAGING  = /tmp/$(APP_NAME)-dmg
VERSION      ?= $(shell date +%Y.%m.%d)

XCODEBUILD   = xcodebuild -scheme $(SCHEME) -configuration Release \
                 CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""

.PHONY: all clean generate arm64 x86_64 dmg-arm64 dmg-x86_64 dmg install

all: generate dmg-arm64 dmg-x86_64
	@echo ""
	@echo "Done! DMGs in $(DIST_DIR)/:"
	@ls -lh $(DIST_DIR)/*.dmg

generate:
	xcodegen generate

arm64:
	@echo "==> Building arm64..."
	$(XCODEBUILD) ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build 2>&1 | tail -3

x86_64:
	@echo "==> Building x86_64..."
	$(XCODEBUILD) ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO build 2>&1 | tail -3

dmg-arm64: arm64
	@$(MAKE) _dmg ARCH=arm64

dmg-x86_64: x86_64
	@$(MAKE) _dmg ARCH=x86_64

dmg: generate dmg-arm64 dmg-x86_64

# Internal target — builds a DMG with an Applications symlink
_dmg:
	@echo "==> Packaging $(APP_NAME)-$(ARCH).dmg..."
	@mkdir -p $(DIST_DIR)
	@rm -rf $(DMG_STAGING)
	@mkdir -p $(DMG_STAGING)
	@cp -R "$(BUILD_BASE)/$(APP_NAME).app" $(DMG_STAGING)/$(APP_NAME).app
	@ln -s /Applications $(DMG_STAGING)/Applications
	@hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(DMG_STAGING) \
		-ov -format UDZO \
		$(DIST_DIR)/$(APP_NAME)-$(ARCH).dmg \
		>/dev/null
	@rm -rf $(DMG_STAGING)
	@echo "==> $(DIST_DIR)/$(APP_NAME)-$(ARCH).dmg"

install: generate
	bash install.sh

clean:
	xcodebuild -scheme $(SCHEME) clean 2>&1 | tail -1
	rm -rf $(DIST_DIR)
