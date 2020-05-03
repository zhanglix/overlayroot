# overlay root file system with a ssd disk

I think Raspiberry Pi 4 is a great low cost self-hosted solution for a lot of applications such as NAS, Photo Management or gitlab, if it is able to use a ssd disk as its fast and reliable storage.

Since we cann't not boot from ssd card for now, I managed to mount an directory from a ssd storage on top of the root file system just before the standard init process.

# What do you need

* A raspberry pi 4 
* a tf-sd card loaded with working raspbian image 
* A ssd disk with a formated partition labled as "portable" (or you need to change the coresponding name in the overlayRoot.sh)

# How to enable it

* copy overlayRoot.sh to /sbin/overlayRoot.sh
* append "init=/sbin/overlayRoot.sh" to /boot/cmdline.txt
* connect the ssd disk to the rapsberry pi
* reboot and wait

```lang=shell
pi@raspberrypi:~ $ ls /sbin/overlayRoot.sh
/sbin/overlayRoot.sh

pi@raspberrypi:~ $ cat /boot/cmdline.txt
console=serial0,115200 console=tty1 root=PARTUUID=738a4d67-02 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait init=/sbin/overlayRoot.sh
```
### Effects
If everything goes well, you will get something like this by run lsblk

```lang=shell
pi@raspberrypi:~ $ lsblk
NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
sda           8:0    0 953.9G  0 disk              
└─sda1        8:1    0 953.9G  0 part /rw           #This is the partition labled as "portable"
mmcblk0     179:0    0  14.9G  0 disk 
├─mmcblk0p1 179:1    0   256M  0 part /boot         #This is the boot partition of the tf-sd card
└─mmcblk0p2 179:2    0  14.6G  0 part /ro           #This is the original rootfs of the tf-sd card which is read only now

```

From now on, all writes will be direct to you ssd storage (specifically to the <portable partition>/overlays directory).


# Reference 

Inspired by an elegant overlayRoot.sh solution from Pascal Suter for running a raspberry pi from a read-only rootfs mount.

This is a beautiful little script that facilitates running a raspberrypi with a read-only mounted filesystem whereby logfiles and other minor writes would then be written to memory only. The result of this is a stable running system that should be pretty much immune from SD card corruption. Read more on Pascal's site for details.

The original can be found here:

http://wiki.psuter.ch/doku.php?id=solve_raspbian_sd_card_corruption_issues_with_read-only_mounted_root_partition

This repo was created in order to aid with the use of this solution in automatic install scripts. The master branch will be kept working for the latest version of raspberrypi. Other branches will be created to support other configurations.
