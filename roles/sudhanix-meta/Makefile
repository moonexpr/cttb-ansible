# gh-77: sudhanix-meta build helper. Runs on the buildworker LXC
# (cttb-ct.sh exec buildworker) — Phase 0 proves the pipeline only.
PKG := sudhanix-meta
VERSION := $(shell dpkg-parsechangelog -ldebian/changelog -SVersion 2>/dev/null)

.PHONY: build publish clean
build:                ## dpkg-buildpackage → ../$(PKG)_$(VERSION)_all.deb
	dpkg-buildpackage -us -uc -b
	@echo "built ../$(PKG)_$(VERSION)_all.deb"

publish: build        ## scp to apt.cttb reprepro inbox + includedeb (same path as vajra)
	scp ../$(PKG)_$(VERSION)_all.deb apt.cttb:/tmp/
	ssh apt.cttb 'reprepro -b /srv/cttb-repos/apt/ubuntu includedeb noble /tmp/$(PKG)_$(VERSION)_all.deb'

clean:                ## drop build artifacts
	dh_clean || true
	rm -f ../$(PKG)_*_all.deb ../$(PKG)_*.buildinfo ../$(PKG)_*.changes
