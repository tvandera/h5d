all: examples

# Variables
BASEDIR=$(PWD)/c_hdf5
HDF5_MAJOR=1
HDF5_MINOR=8
HDF5_RELEASE=23
HDF5_VERSION=$(HDF5_MAJOR).$(HDF5_MINOR).$(HDF5_RELEASE)
HDF5_ARCHIVE=hdf5-$(HDF5_VERSION).tar.gz
HDF5_URL=https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-$(HDF5_MAJOR).$(HDF5_MINOR)/hdf5-$(HDF5_VERSION)/src/$(HDF5_ARCHIVE)

# Default target
all: examples

# Step to create directories
$(BASEDIR)/.dummy:
	mkdir -p $(BASEDIR)
	touch $(BASEDIR)/.dummy

# download
$(BASEDIR)/$(HDF5_ARCHIVE): $(BASEDIR)/.dummy
	wget -q $(HDF5_URL) -O $(BASEDIR)/$(HDF5_ARCHIVE)
	touch $(BASEDIR)/$(HDF5_ARCHIVE)

download: $(BASEDIR)/$(HDF5_ARCHIVE)

# configure, build, and install HDF5
$(BASEDIR)/lib/libhdf5.a: $(BASEDIR)/$(HDF5_ARCHIVE)
	cd $(BASEDIR) && mkdir -p build && cd build && \
	tar -xvzf ../$(HDF5_ARCHIVE) --strip-components 1 && \
	./configure --prefix=$(BASEDIR) --disable-shared && \
	$(MAKE) && \
	$(MAKE) install

lib: $(BASEDIR)/lib/libhdf5.a

# Clean up build directory
clean:
	rm -rf $(BASEDIR)

.PHONY: all download lib clean dub examples

dub: $(BASEDIR)/lib/libhdf5.a
	dub build

test: dub
	dub test --verbose