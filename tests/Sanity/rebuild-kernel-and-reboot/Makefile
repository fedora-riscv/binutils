# Copyright (c) 2009, 2012 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Rebuild kernel, install it, reboot, and check if we're running the correct
# kernel. Tailored specificaly for binutils buildroot testing process.
#
# Author: Milos Prchlik <mprchlik@redhat.com>
#
# Based on gcc/Sanity/rebuild-kernel by:
# Author: Michal Nowak <mnowak@redhat.com>
# Author: Marek Polacek <polacek@redhat.com>


export TEST=/tools/binutils/Sanity/rebuild-kernel-and-reboot
export TESTVERSION=1.0

BUILT_FILES=

FILES=$(METADATA) runtest.sh Makefile PURPOSE

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x ./runtest.sh

clean:
	rm -f *~ $(BUILT_FILES)


include /usr/share/rhts/lib/rhts-make.include


$(METADATA): Makefile
	@echo "Owner:        Milos Prchlik <mprchlik@redhat.com>" > $(METADATA)
	@echo "Name:         $(TEST)" >> $(METADATA)
	@echo "Path:         $(TEST_DIR)"       >> $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"    >> $(METADATA)
	@echo "Description:  Rebuild kernel, install it, reboot, and check if we're running the correct kernel" >> $(METADATA)
	@echo "Type:         Sanity" >> $(METADATA)
	@echo "TestTime:     20h" >> $(METADATA)
	@echo "RunFor:       binutils" >> $(METADATA)
	@echo "Requires:     binutils" >> $(METADATA)
	@echo "Requires:     gcc" >> $(METADATA)
	@echo "Requires:     yum-utils rng-tools" >> $(METADATA)
	@echo "Requires:     rpm-build" >> $(METADATA)
	@echo "Requires:     newt-devel python-devel perl-ExtUtils-Embed unifdef elfutils-libelf-devel" >> $(METADATA)
	@echo "Requires:     elfutils-devel pciutils-devel" >> $(METADATA)
	@echo "Requires:     wget hmaccalc binutils-devel glibc-static texinfo gdb ecj gcc-java ppl-devel cloog-ppl-devel graphviz gmp-devel mpfr-devel" >> $(METADATA)
	@echo "Requires:     xmlto asciidoc net-tools pesign" >> $(METADATA)
	@echo "License:      GPLv3+" >> $(METADATA)

	rhts-lint $(METADATA)
