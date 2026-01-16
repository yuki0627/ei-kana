.PHONY: build start stop clean

APP_NAME = ei-kana
BUILD_DIR = build
APP_PATH = $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app

build:
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release -derivedDataPath $(BUILD_DIR) build

start: stop build
	open $(APP_PATH)

stop:
	-pkill -x $(APP_NAME)

clean:
	rm -rf $(BUILD_DIR)
