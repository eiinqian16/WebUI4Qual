include $(TOPDIR)/rules.mk

PKG_NAME:=webUI
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/eiinqian16/WebUI4Qual.git
PKG_SOURCE_VERSION:=airion-ui
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_SOURCE_VERSION)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.gz
PKG_MIRROR_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/webUI
	SECTION:=web
	CATEGORY:=Web Interface
	TITLE:=Web UI
	DEPENDS:=+uhttpd +luci-base
endef

define Build/Prepare
	$(TAR) -C $(PKG_BUILD_DIR) -xzf $(DL_DIR)/$(PKG_SOURCE)
	if [ -d "$(PKG_BUILD_DIR)/webUI-airion-ui" ]; then \
		mv $(PKG_BUILD_DIR)/webUI-airion-ui/* $(PKG_BUILD_DIR)/; \
		rmdir $(PKG_BUILD_DIR)/webUI-airion-ui; \
	fi
endef

define Build/Compile
	@echo "=== DEBUG: Checking for model file ==="
	@ls -la $(PKG_BUILD_DIR)/ov/ || echo "ov directory not found"
	@/bin/bash -c ' \
		if [ -f "$(PKG_BUILD_DIR)/ov/model" ]; then \
			BOARD_NAME=`cat $(PKG_BUILD_DIR)/ov/model | tr -d "\n\r "`; \
			echo "BOARD_NAME is: $$$$BOARD_NAME"; \
			echo "`date +%Y%m%d-%H%M`-$$$$BOARD_NAME" > $(PKG_BUILD_DIR)/ov/fw_version; \
		else \
			echo "`date +%Y%m%d-%H%M`-Unknown" > $(PKG_BUILD_DIR)/ov/fw_version; \
		fi \
	'
	@echo "=== DEBUG: fw_version content ==="
	@cat $(PKG_BUILD_DIR)/ov/fw_version
endef

define Package/webUI/install
	$(INSTALL_DIR) $(1)/etc/hotplug.d/net/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/hotplug/99-acktimeout $(1)/etc/hotplug.d/net/
	chmod +x $(1)/etc/hotplug.d/net/99-acktimeout

	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/init/acktimeout $(1)/etc/init.d/
	chmod +x $(1)/etc/init.d/acktimeout

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(CP) $(PKG_BUILD_DIR)/98-default-uhttpd $(1)/etc/uci-defaults
	
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/*.sh $(1)/usr/bin/
	chmod +x $(1)/usr/bin/*.sh
	
	$(INSTALL_DIR) $(1)/etc/ui-config
	$(CP) $(PKG_BUILD_DIR)/ui-config/* $(1)/etc/ui-config/

	$(INSTALL_DIR) $(1)/www/webUI/
	$(CP) $(PKG_BUILD_DIR)/css $(1)/www/webUI/
	$(CP) $(PKG_BUILD_DIR)/js $(1)/www/webUI/
	$(CP) $(PKG_BUILD_DIR)/logo $(1)/www/webUI/
	$(CP) $(PKG_BUILD_DIR)/README.md $(1)/www/webUI/
	$(CP) $(PKG_BUILD_DIR)/*.html $(1)/www/webUI/
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(CP) $(PKG_BUILD_DIR)/login $(1)/etc/init.d/login
	$(INSTALL_DIR) $(1)/www/webUI/cgi-bin/
	$(CP) $(PKG_BUILD_DIR)/cgi-bin/* $(1)/www/webUI/cgi-bin/
	chmod +x $(1)/www/webUI/cgi-bin/*
	
	$(INSTALL_DIR) $(1)/www/webUI/ov/
	$(CP) $(PKG_BUILD_DIR)/ov/* $(1)/www/webUI/ov/
	
	$(INSTALL_DIR) $(1)/www/webUI/db/
	$(CP) $(PKG_BUILD_DIR)/db/* $(1)/www/webUI/db/
	
	$(CP) $(1)/www/webUI/ov/fw_version $(BIN_DIR)/
endef

$(eval $(call BuildPackage,webUI))
