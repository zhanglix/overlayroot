#!/bin/sh
#  Read-only Root-FS for Raspian using overlayfs and ssd
#  Version 1.1
#
#  Version History:
#  1.0: initial release
#  1.1: adopted new fstab style with PARTUUID. the script will now look for a /dev/xyz definiton first
#       (old raspbian), if that is not found, it will look for a partition with LABEL=rootfs, if that
#       is not found it look for a PARTUUID string in fstab for / and convert that to a device name
#       using the blkid command.
#
#  Created 2017 by Pascal Suter @ DALCO AG, Switzerland to work on Raspian as custom init script
#  (raspbian does not use an initramfs on boot)
#
#  2.0: only support original root partition labeld by 'rootfs' and ssd partition labeld by 'portable'.
#       All writes are directed to 'portable' ssd partition so you can use your Raspian as a normal server.
#
#  Adapted by James Zhang to make Raspberry an low cost server for NAS and more.
# 
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see
#    <http://www.gnu.org/licenses/>.
#
#
#  Tested with Raspbian GNU/Linux 10 (buster) on Raspberry Pi 4, in May 2020
#
#  This script will mount the root filesystem read-only and overlay it with a directory 
#  on a partition, labeld with "portable", which is read-write mounted. 
#  This is done using the overlayFS which is part of the linux kernel since version 3.18.
#  when this script is in use, all changes made to anywhere in the root filesystem mount will be 
#  directed to overlays directory on the "portable" partition and will be kept permanently.
#  The io perforamance of the system will be much higher with a ssd partition.
#  The SD card will only be accessed as read-only drive, which significantly
#  helps to prolong its life and prevent filesystem coruption in environments where the system is usually
#  not shut down properly
#
#  Install:
#  copy this script to /sbin/overlayRoot.sh, make it executable and add "init=/sbin/overlayRoot.sh" to the
#  cmdline.txt file in the raspbian image's boot partition.
#

fail(){
    echo $@
    exec /sbin/init
    exit 0
}

# load module
modprobe overlay
if [ $? -ne 0 ]; then
    fail "ERROR: missing overlay kernel module"
fi
# mount /proc
mount -t proc proc /proc
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount proc"
fi
# create a writable fs to then create our mountpoints
mount -t tmpfs inittemp /mnt
if [ $? -ne 0 ]; then
    fail "ERROR: could not create a temporary filesystem to mount the base filesystems for overlayfs"
fi

# by james
mkdir /mnt/log
logfile=/mnt/log/overlay_root.log

log(){
    echo $@ >> $logfile
}

log_fail(){
    echo $@ >> $logfile
    exec /sbin/init
}

log "inittemp created!"

mountLabeledDev()
{
    local label=$1
    local option=$2
    local target=$3
    local retry=${4:-10}
    local msg
    log "trying to mount device($label) with option($option) to $target at most $retry times "
    while [ $retry -gt 0 ];
    do
        msg=`blkid |grep 'LABEL="'$label'"'`
        if [ "x$msg" != "x" ]; then
            blkidRetDev=`echo $msg|awk -F: '{print $1}'`
            blkidRetType=`echo $msg | sed -e 's/^.*TYPE="\([^"]*\)".*$/\1/'`
            log "located device. label=$label path=$blkidRetDev, type=$blkidRetType"
            log "mount -t $blkidRetType -o $option  $blkidRetDev $target"
            mount -t $blkidRetType -o $option  $blkidRetDev $target
            if [ $? -ne 0 ]; then
                log "ERROR: Failed to mout $blkidRetDev at $target"
                return 1
            fi
            return 0
        fi
        retry=`expr $retry - 1`
        sleep 1
    done
    return 1
}

#path configs before change root
oldroot=/mnt/readonly
overlayMountPoint=/mnt/readwrite
upperdir=$overlayMountPoint/overlays/rootfs
workdir=$overlayMountPoint/overlays/work
newroot=/mnt/newroot

mkdir -p $oldroot
mountLabeledDev "rootfs" defaults,noatime,ro $oldroot
if [ $? -ne 0 ]; then
    log_fail "Error: Failed to locate rootfs defice"
fi

log "overlayMountPoint=$overlayMountPoint"
mkdir -p $overlayMountPoint
mountLabeledDev "portable" defaults,noatime,rw $overlayMountPoint

if [ $? -ne 0 ]; then
    log "use tmpfs as overlay"
    mount -t tmpfs root-rw $overlayMountPoint
    if [ $? -ne 0 ]; then
        log_fail "ERROR: could not create tempfs for upper filesystem"
    fi
fi

mkdir -p $upperdir
mkdir -p $workdir
mkdir -p $newroot

log "mount -t overlay -o lowerdir=$oldroot,upperdir=$upperdir,workdir=$workdir overlayfs-root $newroot"
mount -t overlay -o lowerdir=$oldroot,upperdir=$upperdir,workdir=$workdir overlayfs-root $newroot
if [ $? -ne 0 ]; then
    log_fail "ERROR: could not mount overlayFS"
fi

# remove root mount from fstab (this is already a non-permanent modification)
grep -v "/ " $oldroot/etc/fstab > $newroot/etc/fstab
echo "#the original root mount has been removed by overlayRoot.sh" >> $newroot/etc/fstab
echo "#this is only a temporary modification, the original fstab" >> $newroot/etc/fstab
echo "#stored on the disk can be found in /ro/etc/fstab" >> $newroot/etc/fstab

# create mountpoints inside the new root filesystem-overlay
mkdir -p $newroot/ro
mkdir -p $newroot/rw
# change to the new overlay root
cd $newroot
put_old=mnt
pivot_root . $put_old
if [ $? -ne 0 ]; then
    log_fail "failed to run: pivot_root . $put_old"
fi

exec chroot . sh -c "$(cat <<END
# move ro and rw mounts to the new root
mount --move /$put_old$oldroot/ /ro
if [ $? -ne 0 ]; then
    echo "ERROR: could not move old-root(/$put_old$oldroot) into newroot" >> /$put_old$logfile
    exec /sbin/init
    exit 0
fi
mount --move /$put_old$overlayMountPoint /rw
if [ $? -ne 0 ]; then
    echo "ERROR: could not move /$put_old$overlayMountPoint into newroot" >> /$put_old$logfile
    exec /sbin/init
    exit 0
fi
# unmount unneeded mounts so we can unmout the old readonly root
umount /$put_old/mnt
umount /$put_old/proc
umount /$put_old/dev
umount /$put_old
# continue with regular init
exec /sbin/init
END
)"
