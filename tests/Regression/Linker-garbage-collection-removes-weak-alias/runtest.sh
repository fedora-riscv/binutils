#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /tools/binutils/Regression/Linker-garbage-collection-removes-weak-alias
#   Description: Test for BZ#1804696 (Linker garbage collection removes weak alias)
#   Author: Martin Cermak <mcermak@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

GCC="${GCC:-$(which gcc)}"
READELF="${READELF:-$(which readelf)}"

GCC_PACKAGE=$(rpm --qf '%{name}\n' -qf $GCC | head -1)
BINUTILS_PACKAGE=$(rpm --qf '%{name}\n' -qf $READELF | head -1)

PACKAGES="${PACKAGE:-$BINUTILS_PACKAGE}"
REQUIRES="${REQUIRES:-$GCC_PACKAGE}"

rlJournalStart
    rlPhaseStartSetup
        rlLogInfo "PACKAGES=$PACKAGES"
        rlLogInfo "REQUIRES=$REQUIRES"
        rlLogInfo "COLLECTIONS=$COLLECTIONS"
        rlLogInfo "READELF=$READELF"
        rlLogInfo "GCC=$GCC"
        rlLogInfo "SKIP_COLLECTION_METAPACKAGE_CHECK=$SKIP_COLLECTION_METAPACKAGE_CHECK"

        # We optionally need to skip checking for the presence of the metapackage
        # because that would pull in all the dependent toolset subrpms.  We do not
        # always want that, especially in CI.
        _COLLECTIONS="$COLLECTIONS"
        if ! test -z $SKIP_COLLECTION_METAPACKAGE_CHECK; then
            for c in $SKIP_COLLECTION_METAPACKAGE_CHECK; do
                rlLogInfo "ignoring metapackage check for collection $c"
                export COLLECTIONS=$(shopt -s extglob && echo ${COLLECTIONS//$c/})
            done
        fi

        rlLogInfo "(without skipped) COLLECTIONS=$COLLECTIONS"

        rlAssertRpm --all

        export COLLECTIONS="$_COLLECTIONS"

        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "cp environ.c $TmpDir/"
        rlRun "pushd $TmpDir"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "gcc -o environ environ.c"
        rlRun "readelf -s -W environ > without-gc-sections.txt"
        rlLogInfo "$(cat without-gc-sections.txt)"
        rlRun "grep ' _environ' without-gc-sections.txt"
        rlRun "gcc -Wl,--gc-sections -o environ environ.c"
        rlRun "readelf -s -W environ > with-gc-sections.txt"
        rlLogInfo "$(cat with-gc-sections.txt)"
        rlRun "grep ' _environ' with-gc-sections.txt"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
