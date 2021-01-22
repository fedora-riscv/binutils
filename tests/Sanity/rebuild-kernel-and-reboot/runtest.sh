#!/bin/bash
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

export AVC_ERROR='+no_avc_check'

case "$JUST_BUILD" in
    0|[Ff][Aa][Ll][Ss][Ee]|[Nn][Oo])
        JUST_BUILD=no
        ;;
    *)
        JUST_BUILD=yes
        ;;
esac

LD="${LD:-$(which ld)}"
GCC="${GCC:-$(which gcc)}"

PACKAGE="${PACKAGE:-$(rpm --qf '%{name}\n' -qf $(which $LD) | head -1)}"
GCC_PACKAGE="${GCC_PACKAGE:-$(rpm --qf '%{name}\n' -qf $(which $GCC) | head -1)}"

PACKAGES="${PACKAGES:-$PACKAGE}"

# Kernel package - usualy "kernel", but some trees may use different package
# name (e.g. kernel-PAE).
KERNEL="${KERNEL:-kernel}"

REQUIRES="${REQUIRES:-$KERNEL $GCC_PACKAGE glibc}"
RPM_BUILD_ID="${RPM_BUILD_ID:-.LimeKitten}"

# Workaround possible restraint issues - restraint may fail to set REBOOTCOUNT properly.
REBOOT_FLAG=/.rebuild-kernel-and-reboot.flag
REBOOTCOUNT="${REBOOTCOUNT:-0}"

unset ARCH

rlJournalStart
    rlPhaseStartSetup
        rlLogInfo "PACKAGES=$PACKAGES"
        rlLogInfo "KERNEL=$KERNEL"
        rlLogInfo "REQUIRES=$REQUIRES"
        rlLogInfo "JUST_BUILD=$JUST_BUILD"
        rlLogInfo "COLLECTIONS=$COLLECTIONS"
        rlLogInfo "SKIP_COLLECTION_METAPACKAGE_CHECK=$SKIP_COLLECTION_METAPACKAGE_CHECK"

        # We'll use a lot of disk space (tens of GBs at least). The root FS
        # often is the most beefy one in CI environemnts. Let's use it but also
        # let's log what's actually available.
        export TMPDIR=/test_tmp_root
        rlRun "mkdir -p $TMPDIR"
        rlLogInfo "TMPDIR=$TMPDIR"
        rlLogInfo 'Disk space:'
        df -h | while read line; do
            rlLogInfo "    $line"
        done

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

        rlRun "AFTER_REBOOT=no"

        if [ "$REBOOTCOUNT" != "0" ]; then
            rlLogInfo "Reboot count envvar is non-zero, update our flag"
            rlRun "AFTER_REBOOT=yes"
        elif [ -f "$REBOOT_FLAG" ]; then
            rlLogInfo "FS reboot flag exists, update our flag"
            rlRun "AFTER_REBOOT=yes"
        fi

        if [ "$AFTER_REBOOT" = "no" ]; then
            # We optionally need to skip checking for the presence of the metapackage
            # because that would pull in all the dependent toolset subrpms.  We do not
            # always want that, especially in CI.
            rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
            rlRun "pushd $TmpDir"

            # Speed up keygen.
            rlRun "rngd -r /dev/hwrandom || rngd -r /dev/urandom"

            # Get the SRPM.
            rlFetchSrcForInstalled "$KERNEL"

            rlRun "SRPM=`find . -name '*.src.rpm'`"
            rlRun "SPECDIR=`rpm --define=\"_topdir $TmpDir\" --eval=%_specdir`"

            rlRun "rpm -ivh --define=\"_topdir $TmpDir\" $SRPM"
            rlRun "SPECFILE=`find $SPECDIR/ -name '*.spec'`"

            builddep_options="--nobest"
            rlRun "yum-builddep -y $builddep_options $SPECFILE"
        fi
    rlPhaseEnd

    if [ "$AFTER_REBOOT" = "no" ]; then
        rlPhaseStartTest "Build"
            if [ "$RPM_BUILD_ID" != "" ]; then
                rlRun "sed -i \"s/# % define buildid .local/%define buildid $RPM_BUILD_ID/\" $SPECFILE"
                rlRun "sed -i \"s/# define buildid .local/%define buildid $RPM_BUILD_ID/\" $SPECFILE"
            fi

            if [ "`rlGetPrimaryArch`" == "ppc64" ]; then 
                TARGET="--target=ppc64"
            else
                TARGET="--target=$(uname -m)"
            fi

            if rlRun "CC=$GCC rpmbuild --define=\"_topdir $TmpDir\" -bb $TARGET --clean $SPECFILE &> BUILD_LOG"; then
                rlRun "RPMBUILD_OK=yes"
            else
                rlLogInfo "rpmbuild kernel failed"
                rlRun "RPMBUILD_OK=no"
            fi
            rlBundleLogs "Build-log" BUILD_LOG
        rlPhaseEnd

        # Install and boot the new kernel only if it's requested *and* the build was successful
        if [ "$JUST_BUILD" = 'no' ] && [ "$RPMBUILD_OK" = "yes" ]; then
            rlPhaseStartTest "Install"
                RPMS="$(ls -1 $TmpDir/RPMS/*/*.rpm | grep -v kernel-selftests-internal | tr '\n' ' ')"

                rlRun "yum localinstall -y --disablerepo=\* $RPMS"

                rlLogInfo "$(rpm -qa | grep kernel | sort)"

                # Update the boot configuration
                if [ "$(arch)" = "s390x" ]; then
                    rlRun "grubby --info=ALL"
                    rlLogInfo "Default kernel is $(grubby --default-kernel), index $(grubby --default-index)"
                    rlRun "KERNEL_FILE=$(ls -1 /boot/vmlinuz-*${RPM_BUILD_ID}.$(arch))"
                    rlRun "ls -al $KERNEL_FILE"
                    rlRun "grubby --set-default $KERNEL_FILE"
                    rlLogInfo "Default kernel is $(grubby --default-kernel), index $(grubby --default-index)"
                    rlRun "zipl"
                else
                    rlRun "grub2-set-default 2"
                fi
            rlPhaseEnd

            rlPhaseStartTest "Reboot"
                rlRun "touch $REBOOT_FLAG"

                rlLog "Rebooting ..."
                rhts-reboot
            rlPhaseEnd
        fi
    fi

    # Verify the build ID only if its install and boot were requested
    if [ "$JUST_BUILD" = 'no' ]; then
        rlPhaseStartTest "Test"
            if ! [ "$AFTER_REBOOT" = 'yes' ]; then
                rlFail 'Not rebooted. Probably rhts-reboot did not work.'
            fi
            rlLogInfo "$(uname -a)"
            rlRun "uname -r | grep $RPM_BUILD_ID"
        rlPhaseEnd
    fi

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
