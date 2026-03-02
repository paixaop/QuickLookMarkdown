SCHEME       = QuickLookMarkdownApp
APP_NAME     = QuickMD
BUILD_BASE   = $(shell xcodebuild -scheme $(SCHEME) -configuration Release \
                 -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')
DIST_DIR     = dist

XCODEBUILD   = xcodebuild -scheme $(SCHEME) -configuration Release \
                 CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""

.PHONY: all clean generate arm64 x86_64 install

all: generate arm64 x86_64
	@echo ""
	@echo "Done! Zip files in $(DIST_DIR)/:"
	@ls -lh $(DIST_DIR)/*.zip

generate:
	xcodegen generate

arm64:
	@echo "==> Building arm64..."
	$(XCODEBUILD) ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build 2>&1 | tail -3
	@mkdir -p $(DIST_DIR)
	@rm -rf /tmp/$(APP_NAME).app
	@cp -R "$(BUILD_BASE)/$(APP_NAME).app" /tmp/$(APP_NAME).app
	@cd /tmp && zip -r -q $(CURDIR)/$(DIST_DIR)/$(APP_NAME)-arm64.zip $(APP_NAME).app
	@rm -rf /tmp/$(APP_NAME).app
	@echo "==> $(DIST_DIR)/$(APP_NAME)-arm64.zip"

x86_64:
	@echo "==> Building x86_64..."
	$(XCODEBUILD) ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO build 2>&1 | tail -3
	@mkdir -p $(DIST_DIR)
	@rm -rf /tmp/$(APP_NAME).app
	@cp -R "$(BUILD_BASE)/$(APP_NAME).app" /tmp/$(APP_NAME).app
	@cd /tmp && zip -r -q $(CURDIR)/$(DIST_DIR)/$(APP_NAME)-x86_64.zip $(APP_NAME).app
	@rm -rf /tmp/$(APP_NAME).app
	@echo "==> $(DIST_DIR)/$(APP_NAME)-x86_64.zip"

install: generate
	bash install.sh

clean:
	xcodebuild -scheme $(SCHEME) clean 2>&1 | tail -1
	rm -rf $(DIST_DIR)
