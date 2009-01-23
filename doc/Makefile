mmm.pdf: mmm.texi mmm_configuration.texi mmm_monitor.texi mmm_internals.texi Makefile
	-rm -r tmp/
	mkdir -p tmp/
	cp mmm*.texi tmp/
	cd tmp && up_menus --nodetail mmm.texi
	cd tmp && pdftex --interaction=nonstopmode mmm.texi
	cd tmp && texindex mmm.??
	cd tmp && pdftex --interaction=nonstopmode mmm.texi
	cp tmp/mmm.pdf .
	cd tmp && makeinfo mmm.texi
	cp tmp/mmm.info .
