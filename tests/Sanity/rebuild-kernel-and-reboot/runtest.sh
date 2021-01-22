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
        rlLogInfo "COLLECTIONS=$COLLECTIONS"
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

            if rlIsRHEL 8; then
                builddep_options="--nobest"
            fi
            rlRun "yum-builddep -y $builddep_options $SPECFILE"
        fi
    rlPhaseEnd

    if [ "$AFTER_REBOOT" = "no" ]; then
        rlPhaseStartTest "Build"
            if [ "$RPM_BUILD_ID" != "" ]; then
                rlRun "sed -i \"s/# % define buildid .local/%define buildid $RPM_BUILD_ID/\" $SPECFILE"

                # This is new, in RHEL8 the line looks different (lacks the '%')... I let reader to
                # think about reasoning behind such change.
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

        # Only install new kernel and reboot if the kernel build went successful
        if [ "$RPMBUILD_OK" = "yes" ]; then
        rlPhaseStartTest "Install"
            # This apparently helps to install the kernel, otherwise the 'yum install' gets collisions :/
            # However, kernel-firmware is in the system repo, and rhel7 needs it... Must experiment more.
            # rlRun "yum erase -y kernel-firmware kernel-tools-libs"

            RPMS="$(ls -1 $TmpDir/RPMS/*/*.rpm | tr '\n' ' ')"

            if rlIsRHEL 8; then
                RPMS="$(ls -1 $TmpDir/RPMS/*/*.rpm | grep -v kernel-selftests-internal | tr '\n' ' ')"
            fi

            rlRun "yum localinstall -y --disablerepo=\* $RPMS"

            rlLogInfo "$(rpm -qa | grep kernel | sort)"

            # On RHEL6 and RHEL7, it was good enough to install packages, and new kernel would be the
            # one to boot. On RHEL8, not anymore, we have to update configuration.
            if rlIsRHEL 8; then

                # Do Nothing!
                # Thanks to /etc/sysconfig/kernel, newly installed kernel is set as default. It is told...

                # Or, use the title. But setting default by the entry title seems to fail. Giving up.
                #
                # rlRun "entry_filename=/boot/loader/entries/*${RPM_BUILD_ID}.$(arch).conf"
                # rlRun "ls -al /boot/loader/entries"
                #
                # Don't wrap it with rlRun, beakerlib gets unhappy :/
                # entry_title="$(grep 'title' $entry_filename | cut -d' ' -f2-)"
                # rlLogInfo "entry_title=$entry_title"
                #
                # rlRun "grub2-mkconfig -o /boot/grub2/grub.cfg"
                # rlRun "grub2-set-default \"$entry_title\""

                # This works - forcing to boot new kernel, and if there are no other kernels, it's just index 2.
                # Apparently, mkconfig sorts the kernels in the opposite way :O - 0. is the old kernel, 1. is
                # the new one's debug kernel, and 2. is the new one...

                # But doesn't work on s390x as there's no grub2-set-default. But there's grubby!

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

                #rlRun "grep '^menuentry' /etc/grub2.cfg > grub_entries"
                #rlRun "cat grub_entries"
                #rlRun "GRUB_ENTRY_NUMBER=$(grep -n $RPM_BUILD_ID grub_entries | grep -v '\+debug' | cut -d':' -f1)"
                #rlAssertEquals "Newly installed kernel should be the first one" "$GRUB_ENTRY_NUMBER" "1"
                #rlRun "grub2-set-default 0"
                #rlAssertEquals "Default boot entry should be 0 (new kernel)" "$(grep saved_entry /boot/grub2/grubenv)" "saved_entry=0"
            fi
        rlPhaseEnd

        rlPhaseStartTest "Reboot"
#            if [[ "`rlGetPrimaryArch`" == "ppc64" ]] || [[ "`rlGetPrimaryArch`" == "ppc64le" ]]; then
#                rlLogWarning "Kernels older than kernel-3.10.0-381.el7 do not boot when built with binutils 2.25.1 on PowerPC boxes"
#                rlLogWarning "This is a temporary, very general warning - I will make it more specific."
#                rlLogWarning "Until then, it is necessary to (build and) reboot the newly build kernel, using the recent enough kernel package."
#            else
              rlRun "touch $REBOOT_FLAG"

            rlLog "Rebooting ..."
            rhts-reboot
#            fi
        rlPhaseEnd
        fi
    fi

    rlPhaseStartTest "Test"
        rlLogInfo "$(uname -a)"
        rlRun "uname -r | grep $RPM_BUILD_ID"
    rlPhaseEnd

    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
