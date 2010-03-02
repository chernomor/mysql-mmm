VERSION= $(shell cat ../VERSION)

mysql-mmm.pdf: mmm.texi mmm_agent.texi mmm_configuration.texi mmm_control.texi mmm_logging.texi mmm_monitor.texi mmm_internals.texi Makefile mysql-mmm.css
	-rm -r tmp/
	mkdir -p tmp/
	cd illustrations && make
	cp illustrations/*.png tmp/
	cp mmm*.texi tmp/
	sed -i 's/!!!VERSION!!!/$(VERSION)/' tmp/mmm.texi
	cd tmp && up_menus --nodetail mmm.texi
	cd tmp && pdftex --interaction=nonstopmode mmm.texi
	cd tmp && texindex mmm.??
	cd tmp && pdftex --interaction=nonstopmode mmm.texi
	cp tmp/mmm.pdf mysql-mmm.pdf
	cd tmp && makeinfo mmm.texi
	cp tmp/mmm.info mysql-mmm.info
	cp mysql-mmm.css tmp/
	cd tmp && texi2html --css-include mysql-mmm.css mmm.texi
	cp tmp/mmm.html mysql-mmm.html
	cp tmp/mmm-sample-setup-1.png tmp/mmm-sample-setup-2.png .

clean:
	rm -rf tmp
	rm -f mysql-mmm.info mysql-mmm.pdf mysql-mmm.html mmm-sample-setup-1.png mmm-sample-setup-2.png
