
PACKAGENAME=mysql-mmm
VERSION= $(shell cat VERSION)
RELEASEDIR=release

.PHONY: release release-archives release-debs

test: 
	cd lib/Agent/t && prove
	cd lib/Monitor/t && prove
	cd lib/Common/t && prove

test-v: 
	cd lib/Agent/t && prove -v
	cd lib/Monitor/t && prove -v
	cd lib/Common/t && prove -v

release: release-archives release-debs

release-archives:
	rm -rf $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION)/
	mkdir -p $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION)
	cp -r lib bin sbin etc $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION)
	cp Makefile.release $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION)/Makefile
	cp README INSTALL COPYING VERSION $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION)/
	find $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION) -depth -type d -name '.svn' -exec rm -rf {} \;
	find $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION) -depth -type d -name 't' -exec rm -rf {} \;
	find $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION) -depth -type f -name '*.swp' -exec rm -rf {} \;
	tar -C $(RELEASEDIR) -cjf $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION).tar.bz2 $(PACKAGENAME)-$(VERSION)/
	tar -C $(RELEASEDIR) -czf $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION).tar.gz $(PACKAGENAME)-$(VERSION)/

release-debs: release-archives
	cp $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION).tar.gz $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION).orig.tar.gz
	cp -r debian $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION)/
	rm -rf $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION)/debian/.svn/
	-cd $(RELEASEDIR)/$(PACKAGENAME)-$(VERSION)/ && dpkg-buildpackage -rfakeroot
	
