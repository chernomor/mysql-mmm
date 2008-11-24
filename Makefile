
test: 
	cd lib/Agent/t && prove
	cd lib/Monitor/t && prove
	cd lib/Common/t && prove

test-v: 
	cd lib/Agent/t && prove -v
	cd lib/Monitor/t && prove -v
	cd lib/Common/t && prove -v
