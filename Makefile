.PHONY: all fetch deb clean help

all: deb

fetch:
	@chmod +x fetch_assets.sh
	./fetch_assets.sh

deb:
	@chmod +x build_deb.sh
	./build_deb.sh

clean:
	rm -f *.deb

help:
	@echo "Available targets:"
	@echo "  make fetch - Download Mihomo binary and Zashboard WebUI"
	@echo "  make deb   - Package the .deb archive using dpkg-deb"
	@echo "  make clean - Remove built deb packages"
