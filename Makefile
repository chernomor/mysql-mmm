
RELEASEDIR = release


test: 
	cd lib/Agent/t && prove
	cd lib/Monitor/t && prove
	cd lib/Common/t && prove

test-v: 
	cd lib/Agent/t && prove -v
	cd lib/Monitor/t && prove -v
	cd lib/Common/t && prove -v

release: 
	mkdir -p $(RELEASEDIR)
	cp -r lib bin sbin etc $(RELEASEDIR)
	cp Makefile.release $(RELEASEDIR)/Makefile
	find $(RELEASEDIR) -depth -type d -name '.svn' -exec rm -rf {} \;
	find $(RELEASEDIR) -depth -type d -name 't' -exec rm -rf {} \;
	find $(RELEASEDIR) -depth -type f -name '*.swp' -exec rm -rf {} \;
