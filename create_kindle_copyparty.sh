#!/usr/bin/env bash

REPO="http://dl-cdn.alpinelinux.org/alpine"
MNT="/mnt/kindle_copyparty"
IMAGE="./kindle_copyparty.ext3"
IMAGESIZE=512 #Megabytes
exec 3>&1 4>&2
exec >/dev/null 2>&1
ALPINESETUP="source /etc/profile
echo Kindle_Copyparty > /etc/hostname
echo \"nameserver 1.1.1.1\" > /etc/resolv.conf
mkdir /run/dbus
apk update
apk upgrade
apk add openssh vim curl git wget net-tools iproute2 sudo bash 
apk add python3 py3-pillow ffmpeg py3-pip
adduser alpine -D
echo -e \"alpine\nalpine\" | passwd alpine
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers
addgroup sudo
addgroup alpine sudo
su alpine -c \"cd ~
mkdir -p /kindle/copyparty/srv 
#curl -L -o /kindle/copyparty/srv/copyparty-sfx.py https://github.com/9001/copyparty/releases/latest/download/copyparty-sfx.py
#sudo iptables -A INPUT -p tcp --dport 3923 -j ACCEPT

echo \"You're now dropped into an interactive shell in Alpine, Type exit to leave.\"
sh"

STARTKINDLECOPYPARTY='#!/bin/sh
chmod a+w /dev/shm 
curl -L -o /kindle/copyparty/copyparty-sfx.py https://github.com/9001/copyparty/releases/latest/download/copyparty-sfx.py
COPYPARTY_CMD="python3 /kindle/copyparty/copyparty-sfx.py -c /kindle/copyparty/copyparty.conf"
exec /bin/bash -i -c "$COPYPARTY_CMD; exec /bin/bash"

' 
COPYPARTYCONFIG='
[global]
  # listen on port 3923
  i: 0.0.0.0
  e2dsa, e2ts, z, qr, sss       # enable file indexing and filesystem scanning
  # and enable multimedia indexing
  # and zeroconf and qrcode (you can comma-separate arguments)
  
# create users:
[accounts]
  kindle: copyparty   # username: password

# create volumes:
[/]         # create a volume at "/" (the webroot), which will
  /kindle/copyparty/srv        # share the contents of "/kindle/copyparty/srv" (the current directory)
  accs:
    r: *    # everyone gets read-access, but
    rw: kindle  # the user "kindle" gets read-write
'

# ENSURE ROOT
# This script needs root access to e.g. mount the image
[ "$(whoami)" != "root" ] && echo "This script needs to be run as root" && exec sudo -- "$0" "$@"


# GETTING APK-TOOLS-STATIC
# This tool is used to bootstrap Alpine Linux. It is hosted in the Alpine repositories like any other package, and we need to
# read in the APKINDEX what version it is currently to get the correct download link. It is extracted in /tmp and deleted
# again at the end of the script
#echo "Determining version of apk-tools-static"
curl "$REPO/latest-stable/main/armhf/APKINDEX.tar.gz" --output /tmp/APKINDEX.tar.gz
tar -xzf /tmp/APKINDEX.tar.gz -C /tmp
APKVER="$(cut -d':' -f2 <<<"$(grep -A 5 "P:apk-tools-static" /tmp/APKINDEX | grep "V:")")"  # Grep for the version in APKINDEX
rm /tmp/APKINDEX /tmp/APKINDEX.tar.gz /tmp/DESCRIPTION # Remove what we downloaded and extracted
#echo "Version of apk-tools-static is: $APKVER"
#echo "Downloading apk-tools-static"
curl "$REPO/latest-stable/main/armv7/apk-tools-static-$APKVER.apk" --output "/tmp/apk-tools-static.apk"
tar -xzf "/tmp/apk-tools-static.apk" -C /tmp # extract apk-tools-static to /tmp


# CREATING IMAGE FILE
# To create the image file, a file full of zeros with the desired size is created using dd. An ext3-filesystem is created in it.
# Also automatic checks are disabled using tune2fs
#echo "Creating image file"
dd if=/dev/zero of="$IMAGE" bs=1M count=$IMAGESIZE
mkfs.ext3 "$IMAGE"
tune2fs -i 0 -c 0 "$IMAGE"


# MOUNTING IMAGE
# The mountpoint is created (doesn't matter if it exists already) and the empty ext3-filsystem is mounted in it
#echo "Mounting image"
mkdir -p "$MNT"
mount -o loop -t ext3 "$IMAGE" "$MNT"


# BOOTSTRAPPING ALPINE
# Here most of the magic happens. The apk tool we extracted earlier is invoked to create the root filesystem of Alpine inside the
# mounted image. We use the arm-version of it to end up with a root filesystem for arm. Also the "edge" repository is used
# to end up with the newest software, some of which is very useful for Kindles
#echo "Bootstrapping Alpine"
qemu-arm-static /tmp/sbin/apk.static -X "$REPO/edge/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base


# COMPLETE IMAGE MOUNTING FOR CHROOT
# Some more things are needed inside the chroot to be able to work in it (for network connection etc.)
mount /dev/ "$MNT/dev/" --bind
mount -t proc none "$MNT/proc"
mount -o bind /sys "$MNT/sys"


# CONFIGURE ALPINE
# Some configuration needed
cp /etc/resolv.conf "$MNT/etc/resolv.conf" # Copy resolv from host for internet connection
# Configure repositories for apk (edge main+community+testing for lots of useful and up-to-date software)
mkdir -p "$MNT/etc/apk"
echo "$REPO/edge/main/
$REPO/edge/community/
$REPO/edge/testing/
$REPO/latest-stable/community" > "$MNT/etc/apk/repositories"
# Create the script to start the gui
echo "$STARTKINDLECOPYPARTY" > "$MNT/start_kindle_copyparty.sh"
mkdir -p "$MNT/kindle/copyparty/srv" 
echo "$COPYPARTYCONFIG" > "$MNT/kindle/copyparty/copyparty.conf"
chmod +x "$MNT/start_kindle_copyparty.sh"


# CHROOT
# Here we run arm-software inside the Alpine container, and thus we need the qemu-arm-static binary in it
cp $(which qemu-arm-static) "$MNT/usr/bin/"
# Chroot and run the setup as specified at the beginning of the script
#echo "Chrooting into Alpine"
chroot /mnt/kindle_copyparty/ qemu-arm-static /bin/sh -c "$ALPINESETUP > /dev/null 2>&1"
exec 1>&3 2>&4

ALPINE_VERSION=$(sudo chroot /mnt/kindle_copyparty cat /etc/alpine-release)

# Print the Alpine version to the host
echo "ALPINE_VERSION=$ALPINE_VERSION" 

exec >/dev/null 2>&1

# Remove the qemu-arm-static binary again, it's not needed on the kindle
rm "$MNT/usr/bin/qemu-arm-static"
 
# UNMOUNT IMAGE & CLEANUP
# Sync to disc
sync
# Kill remaining processes
kill $(lsof +f -t "$MNT")
# We unmount in reverse order
#echo "Unmounting image"
umount "$MNT/sys"
umount "$MNT/proc"
umount -lf "$MNT/dev"
umount "$MNT"
while [[ $(mount | grep "$MNT") ]]
do
#	echo "Alpine is still mounted, please wait.."
	sleep 3
	umount "$MNT"
done
#echo "Alpine unmounted"

# And remove the apk-tools-static which we extracted to /tmp
#echo "Cleaning up"
rm /tmp/apk-tools-static.apk
rm -r /tmp/sbin
