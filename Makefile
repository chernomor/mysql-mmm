
MODULEDIR = $(DESTDIR)$(shell eval "`perl -V:installvendorlib`"; echo $$installvendorlib)/MMM
BINDIR    = $(DESTDIR)/usr/bin/mysql-mmm
SBINDIR   = $(DESTDIR)/usr/sbin/


blubb:
	echo "$(MODULEDIR) $(BINDIR) $(SBINDIR)"

test: 
	cd lib/Agent/t && prove
	cd lib/Monitor/t && prove
	cd lib/Common/t && prove

test-v: 
	cd lib/Agent/t && prove -v
	cd lib/Monitor/t && prove -v
	cd lib/Common/t && prove -v

install: 
	mkdir -p $(DESTDIR) $(MODULEDIR) $(BINDIR) $(SBINDIR)
	cp -r lib/* $(MODULEDIR)/
	find $(MODULEDIR) -depth -type d -name '.svn' -exec rm -rf {} \;
	find $(MODULEDIR) -depth -type d -name 't' -exec rm -rf {} \;
	cp -r bin/agent $(BINDIR)
	cp -r bin/monitor $(BINDIR)
	rm -rf $(BINDIR)/agent/.svn
	rm -rf $(BINDIR)/monitor/.svn
	cp sbin/mmm* $(SBINDIR)
