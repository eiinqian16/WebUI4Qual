include $(TOPDIR)/rules.mk

PKG_NAME:=webUI
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/eiinqian16/WebUI4Qual.git
PKG_SOURCE_VERSION:=main
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
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -C $(PKG_BUILD_DIR) -xzf $(DL_DIR)/$(PKG_SOURCE)
	mv $(PKG_BUILD_DIR)/webUI-main/* $(PKG_BUILD_DIR)/
	# Remove the now-empty webUI-0~main directory
	rm -rf $(PKG_BUILD_DIR)/webUI-0~main
endef

define Build/Compile
	# No compilation needed, just extract files
	true
endef

define Package/webUI/install
	$(INSTALL_DIR) $(1)/www/test/
	$(CP) $(PKG_BUILD_DIR)/css $(1)/www/test/
	$(CP) $(PKG_BUILD_DIR)/js $(1)/www/test/
	$(CP) $(PKG_BUILD_DIR)/logo $(1)/www/test/
	$(CP) $(PKG_BUILD_DIR)/README.md $(1)/www/test/
	$(CP) $(PKG_BUILD_DIR)/*.html $(1)/www/test/
	$(INSTALL_DIR) $(1)/etc/config/
	$(CP) $(PKG_BUILD_DIR)/*.txt $(1)/etc/config/login
	$(INSTALL_DIR) $(1)/www/test/cgi-bin/
	$(CP) $(PKG_BUILD_DIR)/cgi-bin/* $(1)/www/test/cgi-bin/
	chmod +x $(1)/www/test/cgi-bin/*
endef


$(eval $(call BuildPackage,webUI))
