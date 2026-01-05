#!/bin/sh

ALREADYMOUNTED="no"
if [ "$(mount | grep /tmp/kindle_copyparty)" ] ; then
	ALREADYMOUNTED="yes"
	echo "ATTENTION! Alpine's rootfs is already mounted, so you will be dropped into it."
	echo "BE CAREFUL to leave this shell first, as there will be no umount either (To not disturb the other session)."
   else
	echo "Mounting Alpine rootfs"
	mkdir -p /tmp/kindle_copyparty
	mount -o loop,noatime -t ext3 /mnt/us/extensions/kindle_copyparty/kindle_copyparty.ext3 /tmp/kindle_copyparty
	mount -o bind /dev /tmp/kindle_copyparty/dev
	mount -o bind /dev/pts /tmp/kindle_copyparty/dev/pts
	mount -o bind /proc /tmp/kindle_copyparty/proc
	mount -o bind /sys /tmp/kindle_copyparty/sys
	mount -o bind /var/run/dbus/ /tmp/kindle_copyparty/run/dbus/
	mkdir -p /mnt/us/extensions/kindle_copyparty/copyparty/srv
    mkdir -p /tmp/kindle_copyparty/kindle/copyparty/srv
    mount -o bind /mnt/us/extensions/kindle_copyparty/copyparty/srv /tmp/kindle_copyparty/kindle/copyparty/srv
    cp /etc/hosts /tmp/kindle_copyparty/etc/hosts
	chmod a+w /dev/shm
	iptables -A INPUT -p tcp --dport 3923 -j ACCEPT

fi

echo "You're now being dropped into Alpine's shell"
chroot /tmp/kindle_copyparty /bin/sh

if [ $ALREADYMOUNTED = "yes" ] ; then
	echo "Umount is being skipped, as the rootfs was mounted already. You're now at your kindle's shell again."
else
	echo "You returned from Alpine, killing remaining processes"
	kill -9 $(lsof -t /var/tmp/kindle_copyparty/)

	echo "Unmounting Alpine! "
	LOOPDEV="$(mount | grep loop | grep /tmp/kindle_copyparty | cut -d" " -f1)"
	umount /tmp/kindle_copyparty/kindle/copyparty/srv
	umount /tmp/kindle_copyparty/run/dbus/
	umount /tmp/kindle_copyparty/sys
	sleep 3
	umount /tmp/kindle_copyparty/proc
	umount /tmp/kindle_copyparty/dev/pts
	umount /tmp/kindle_copyparty/dev
	sync
	umount /tmp/kindle_copyparty || true
	# Sometimes it fails still and only works by trying again
	while [ "$(mount | grep /tmp/kindle_copyparty)" ]
	do
		echo "Alpine is still mounted, trying again..."
		sleep 5
		umount /tmp/kindle_copyparty || true
	done
	echo "Unmounted!"
	losetup -d $LOOPDEV
	echo "All done, You're now back in the kindle shell."
fi
