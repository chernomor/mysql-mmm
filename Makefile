
test: 
	cd lib/Agent/t && prove
	cd lib/Common/t && prove

test-v: 
	cd lib/Agent/t && prove -v
	cd lib/Common/t && prove -v
