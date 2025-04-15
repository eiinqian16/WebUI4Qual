include $(TOPDIR)/rules.mk

PKG_NAME:=compex-web-ui
PKG_RELEASE:=1

WEBUI_DIR_NAME:=compex-web-ui

#web ui path
WEBUI_DIR=webUI_WPQ530MR

include $(INCLUDE_DIR)/package.mk

define Package/compex-web-ui
	SECTION:=web
	CATEGORY:=Web Interface
	TITLE:=Compex Web UI
	DEPENDS:=+uhttpd +luci-base
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	cp -r $(TOPDIR)/package/system/compex-web-ui/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	true
endef

define Package/compex-web-ui/install
	#hotplug
	$(INSTALL_DIR) $(1)/etc/hotplug.d/net/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/hotplug/99-acktimeout $(1)/etc/hotplug.d/net/
	chmod +x $(1)/etc/hotplug.d/net/99-acktimeout

	#init 
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/init/acktimeout $(1)/etc/init.d/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/init/mld_phyname $(1)/etc/init.d/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/login $(1)/etc/config/
	chmod +x $(1)/etc/init.d/acktimeout
	chmod +x $(1)/etc/init.d/mld_phyname

	#Web UI 
	$(INSTALL_DIR) $(1)/www/$(WEBUI_DIR_NAME)/
	$(CP) $(PKG_BUILD_DIR)/$(WEBUI_DIR)/* $(1)/www/$(WEBUI_DIR_NAME)/

	#cgi-bin
	$(INSTALL_DIR) $(1)/www/$(WEBUI_DIR_NAME)/cgi-bin/
	$(CP) $(PKG_BUILD_DIR)/$(WEBUI_DIR)/cgi-bin/* $(1)/www/$(WEBUI_DIR_NAME)/cgi-bin/
	chmod +x $(1)/www/$(WEBUI_DIR_NAME)/cgi-bin/*
endef


$(eval $(call BuildPackage,compex-web-ui))

