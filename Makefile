# --- Configuration ---
FRIDA_VERSION := 17.3.0
YOUTUBE_IPA   := ./ipa/YouTube_4.51.08_decrypted.ipa

# NOTE: These addresses are specific to the YouTube version above.
# If you change the YOUTUBE_IPA, you MUST find new addresses.
GUM_GRAFT_ADDR_1 := 0xed5270
GUM_GRAFT_ADDR_2 := 0x152d508
# --- End Configuration ---


GUM_GRAFT := ./bin/gum-graft-$(FRIDA_VERSION)-macos-arm64

.PHONY: all
all: mutube.ipa

# Rule to download the gum-graft tool if it's missing
$(GUM_GRAFT):
	@echo "Downloading gum-graft..."
	mkdir -p ./bin
	wget https://github.com/frida/frida/releases/download/$(FRIDA_VERSION)/gum-graft-$(FRIDA_VERSION)-macos-arm64.xz -P ./bin
	unxz -k ./bin/gum-graft-$(FRIDA_VERSION)-macos-arm64.xz
	chmod +x ./bin/gum-graft-$(FRIDA_VERSION)-macos-arm64

# Main rule to build the patched IPA
mutube.ipa: $(YOUTUBE_IPA) $(GUM_GRAFT) main.js script_config.json
	# Create a temporary directory for processing
	$(eval TMPDIR := $(shell mktemp -d ./.make-tmp_XXXXXXXX))

	# Download and extract the Frida gadget
	@echo "Downloading Frida gadget..."
	wget -q https://github.com/frida/frida/releases/download/$(FRIDA_VERSION)/frida-gadget-$(FRIDA_VERSION)-tvos-arm64.dylib.xz -O $(TMPDIR)/frida-gadget.dylib.xz
	unxz -k $(TMPDIR)/frida-gadget.dylib.xz

	# Unzip the original IPA
	@echo "Unzipping original IPA..."
	mkdir -p $(TMPDIR)/yt-unzip
	unzip -q $(YOUTUBE_IPA) -d $(TMPDIR)/yt-unzip

	# --- Dynamic Path Finding (The Fix) ---
	# Find the .app path automatically instead of hardcoding it
	$(eval APP_PATH := $(shell find $(TMPDIR)/yt-unzip/Payload -name "*.app" -maxdepth 1))
	@echo "Found app at: $(APP_PATH)"
	
	# Find the executable name from the Info.plist
	$(eval EXECUTABLE_NAME := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' $(APP_PATH)/Info.plist))
	$(eval EXECUTABLE_PATH := $(APP_PATH)/$(EXECUTABLE_NAME))
	@echo "Found executable at: $(EXECUTABLE_PATH)"
	# --- End Dynamic Path Finding ---

	# Inject all the files into the unzipped .app folder
	@echo "Injecting files..."
	mv $(TMPDIR)/frida-gadget.dylib $(APP_PATH)/Frameworks/FridaGadget.dylib
	cp ./script_config.json $(APP_PATH)/FridaGadget.config
	cp ./main.js $(APP_PATH)/main.js

	# Instrument the app executable with gum-graft
	@echo "Instrumenting executable with gum-graft..."
	$(GUM_GRAFT) $(EXECUTABLE_PATH) --instrument=$(GUM_GRAFT_ADDR_1) --instrument=$(GUM_GRAFT_ADDR_2)
	
	# Inject the dylib into the executable
	@echo "Injecting dylib..."
	insert_dylib --strip-codesig --inplace '@executable_path/Frameworks/FridaGadget.dylib' $(EXECUTABLE_PATH)

	# Zip the patched files into the new mutube.ipa
	@echo "Zipping new mutube.ipa..."
	cd $(TMPDIR)/yt-unzip && zip -qr injected.ipa Payload
	mv $(TMPMDIR)/yt-unzip/injected.ipa mutube.ipa

	# Clean up the temporary directory
	@echo "Cleaning up..."
	rm -rf $(TMPDIR)
	@echo "Done! mutube.ipa created."

.PHONY: clean
clean:
	@echo "Cleaning up temporary files and mutube.ipa..."
	rm -rf ./.make-tmp_* mutube.ipa
