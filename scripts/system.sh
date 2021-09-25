#!/bin/bash
#
# QNAS system build script
# Optional parameteres below:
set -o nounset
set -o errexit

export LC_ALL=POSIX
export CONFIG_HOST=$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')

export CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc"
export CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++"
export AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar"
export AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as"
export LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld"
export RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib"
export READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf"
export STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip"

CONFIG_PKG_VERSION="QNAS x86_64 2021.09"
CONFIG_BUG_URL="https://github.com/LeeKyuHyuk/QNAS/issues"

# End of optional parameters
function step() {
	echo -e "\e[7m\e[1m>>> $1\e[0m"
}

function success() {
	echo -e "\e[1m\e[32m$1\e[0m"
}

function error() {
	echo -e "\e[1m\e[31m$1\e[0m"
}

function extract() {
	case $1 in
	*.tgz) tar -zxf $1 -C $2 ;;
	*.tar.gz) tar -zxf $1 -C $2 ;;
	*.tar.bz2) tar -jxf $1 -C $2 ;;
	*.tar.xz) tar -Jxf $1 -C $2 ;;
	esac
}

function check_environment_variable {
	if ! [[ -d $SOURCES_DIR ]]; then
		error "Please download tarball files!"
		error "Run 'make download'."
		exit 1
	fi
}

function check_tarballs {
	LIST_OF_TARBALLS="
    "

	for tarball in $LIST_OF_TARBALLS; do
		if ! [[ -f $SOURCES_DIR/$tarball ]]; then
			error "Can't find '$tarball'!"
			exit 1
		fi
	done
}

function timer {
	if [[ $# -eq 0 ]]; then
		echo $(date '+%s')
	else
		local stime=$1
		etime=$(date '+%s')
		if [[ -z "$stime" ]]; then stime=$etime; fi
		dt=$((etime - stime))
		ds=$((dt % 60))
		dm=$(((dt / 60) % 60))
		dh=$((dt / 3600))
		printf '%02d:%02d:%02d' $dh $dm $ds
	fi
}

check_environment_variable
check_tarballs
total_build_time=$(timer)

rm -rf $BUILD_DIR $ROOTFS_DIR
mkdir -pv $BUILD_DIR $ROOTFS_DIR

step "[1/22] Create root file system directory."
rm -rf $ROOTFS_DIR
mkdir -pv $ROOTFS_DIR/{boot,bin,dev,etc,lib,media,mnt,opt,proc,root,run,sbin,sys,tmp,usr}
ln -snvf lib $ROOTFS_DIR/lib64
mkdir -pv $ROOTFS_DIR/dev/{pts,shm}
mkdir -pv $ROOTFS_DIR/etc/{network,profile.d}
mkdir -pv $ROOTFS_DIR/etc/network/{if-down.d,if-post-down.d,if-pre-up.d,if-up.d}
mkdir -pv $ROOTFS_DIR/usr/{bin,lib,sbin}
ln -snvf lib $ROOTFS_DIR/usr/lib64
mkdir -pv $ROOTFS_DIR/var/lib

step "[2/22] Creating Essential Files and Symlinks"
# Create /etc/passwd
cat >$ROOTFS_DIR/etc/passwd <<"EOF"
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/bin/false
bin:x:2:2:bin:/bin:/bin/false
sys:x:3:3:sys:/dev:/bin/false
sync:x:4:100:sync:/bin:/bin/sync
mail:x:8:8:mail:/var/spool/mail:/bin/false
www-data:x:33:33:www-data:/var/www:/bin/false
operator:x:37:37:Operator:/var:/bin/false
nobody:x:65534:65534:nobody:/home:/bin/false
EOF
# Create /etc/shadow
cat >$ROOTFS_DIR/etc/shadow <<"EOF"
root::10933:0:99999:7:::
daemon:*:10933:0:99999:7:::
bin:*:10933:0:99999:7:::
sys:*:10933:0:99999:7:::
sync:*:10933:0:99999:7:::
mail:*:10933:0:99999:7:::
www-data:*:10933:0:99999:7:::
operator:*:10933:0:99999:7:::
nobody:*:10933:0:99999:7:::
EOF
sed -i -e s,^root:[^:]*:,root:"$($TOOLS_DIR/bin/mkpasswd -m "sha-512" "$CONFIG_ROOT_PASSWD")":, $ROOTFS_DIR/etc/shadow
# Create /etc/passwd
cat >$ROOTFS_DIR/etc/group <<"EOF"
root:x:0:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:8:
kmem:x:9:
wheel:x:10:root
cdrom:x:11:
dialout:x:18:
floppy:x:19:
video:x:28:
audio:x:29:
tape:x:32:
www-data:x:33:
operator:x:37:
mysql:x:40:
utmp:x:43:
plugdev:x:46:
staff:x:50:
lock:x:54:
netdev:x:82:
users:x:100:
nogroup:x:65534:
EOF
echo "Welcome to QNAS on the Docker" >$ROOTFS_DIR/etc/issue
ln -svf /proc/self/mounts $ROOTFS_DIR/etc/mtab
ln -svf /tmp $ROOTFS_DIR/var/cache
ln -svf /tmp $ROOTFS_DIR/var/lib/misc
ln -svf /tmp $ROOTFS_DIR/var/lock
ln -svf /tmp $ROOTFS_DIR/var/log
ln -svf /tmp $ROOTFS_DIR/var/run
ln -svf /tmp $ROOTFS_DIR/var/spool
ln -svf /tmp $ROOTFS_DIR/var/tmp
ln -svf /tmp/log $ROOTFS_DIR/dev/log
ln -svf /tmp/resolv.conf $ROOTFS_DIR/etc/resolv.conf

step "[3/22] Copy GCC 11.2.0 Library"
cp -v $TOOLS_DIR/$CONFIG_TARGET/lib64/libgcc_s* $ROOTFS_DIR/lib/
cp -v $TOOLS_DIR/$CONFIG_TARGET/lib64/libatomic* $ROOTFS_DIR/lib/

step "[4/22] Libstdc++ from Gcc 11.2.0"
for libstdc in libstdc++; do
	cp -dpvf $TOOLS_DIR/$CONFIG_TARGET/lib*/$libstdc.a $ROOTFS_DIR/usr/lib/
done
for libstdc in libstdc++; do
	cp -dpvf $TOOLS_DIR/$CONFIG_TARGET/lib*/$libstdc.so* $ROOTFS_DIR/usr/lib/
done

step "[5/22] musl 1.2.2"
extract $SOURCES_DIR/musl-1.2.2.tar.gz $BUILD_DIR
sed -i 's@/dev/null/utmp@/var/log/utmp@g' $BUILD_DIR/musl-1.2.2/include/paths.h
sed -i 's@/dev/null/wtmp@/var/log/wtmp@g' $BUILD_DIR/musl-1.2.2/include/paths.h
mkdir $BUILD_DIR/musl-1.2.2/musl-build
(cd $BUILD_DIR/musl-1.2.2/musl-build &&
	$BUILD_DIR/musl-1.2.2/configure \
		CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" \
		--prefix=/usr \
		--target=$CONFIG_TARGET \
		--enable-static)
make -j$PARALLEL_JOBS -C $BUILD_DIR/musl-1.2.2/musl-build
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/musl-1.2.2/musl-build
install -m 0644 -D $SUPPORT_DIR/musl/queue.h $ROOTFS_DIR/include/sys/queue.h
rm -rf $BUILD_DIR/musl-1.2.2

step "[6/22] Busybox 1.34.0"
extract $SOURCES_DIR/busybox-1.34.0.tar.bz2 $BUILD_DIR
make -j$PARALLEL_JOBS distclean -C $BUILD_DIR/busybox-1.34.0
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH defconfig -C $BUILD_DIR/busybox-1.34.0
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" -C $BUILD_DIR/busybox-1.34.0
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" CONFIG_PREFIX=$ROOTFS_DIR install -C $BUILD_DIR/busybox-1.34.0
if grep -q "CONFIG_UDHCPC=y" $BUILD_DIR/busybox-1.34.0/.config; then
	mkdir -pv $ROOTFS_DIR/usr/share/udhcpc
	cat >$ROOTFS_DIR/usr/share/udhcpc/default.script <<"EOF"
#!/bin/sh
# udhcpc script edited by Tim Riker <Tim@Rikers.org>
[ -z "$1" ] && echo "Error: should be called from udhcpc" && exit 1
RESOLV_CONF="/etc/resolv.conf"
[ -e $RESOLV_CONF ] || touch $RESOLV_CONF
[ -n "$broadcast" ] && BROADCAST="broadcast $broadcast"
[ -n "$subnet" ] && NETMASK="netmask $subnet"
case "$1" in
	deconfig)
		/sbin/ifconfig $interface up
		/sbin/ifconfig $interface 0.0.0.0
		# drop info from this interface
		# resolv.conf may be a symlink to /tmp/, so take care
		TMPFILE=$(mktemp)
		grep -vE "# $interface\$" $RESOLV_CONF > $TMPFILE
		cat $TMPFILE > $RESOLV_CONF
		rm -f $TMPFILE
		if [ -x /usr/sbin/avahi-autoipd ]; then
			/usr/sbin/avahi-autoipd -k $interface
		fi
		;;
	leasefail|nak)
		if [ -x /usr/sbin/avahi-autoipd ]; then
			/usr/sbin/avahi-autoipd -wD $interface --no-chroot
		fi
		;;
	renew|bound)
		if [ -x /usr/sbin/avahi-autoipd ]; then
			/usr/sbin/avahi-autoipd -k $interface
		fi
		/sbin/ifconfig $interface $ip $BROADCAST $NETMASK
		if [ -n "$router" ] ; then
			echo "deleting routers"
			while route del default gw 0.0.0.0 dev $interface 2> /dev/null; do
				:
			done
			for i in $router ; do
				route add default gw $i dev $interface
			done
		fi
		# drop info from this interface
		# resolv.conf may be a symlink to /tmp/, so take care
		TMPFILE=$(mktemp)
		grep -vE "# $interface\$" $RESOLV_CONF > $TMPFILE
		cat $TMPFILE > $RESOLV_CONF
		rm -f $TMPFILE
		# prefer rfc3359 domain search list (option 119) if available
		if [ -n "$search" ]; then
			search_list=$search
		elif [ -n "$domain" ]; then
			search_list=$domain
		fi
		[ -n "$search_list" ] &&
			echo "search $search_list # $interface" >> $RESOLV_CONF
		for i in $dns ; do
			echo adding dns $i
			echo "nameserver $i # $interface" >> $RESOLV_CONF
		done
		;;
esac
HOOK_DIR="$0.d"
for hook in "${HOOK_DIR}/"*; do
    [ -f "${hook}" -a -x "${hook}" ] || continue
    "${hook}" "${@}"
done
exit 0
EOF
	chmod -v 0755 $ROOTFS_DIR/usr/share/udhcpc/default.script
	install -m 0755 -dv $ROOTFS_DIR/usr/share/udhcpc/default.script.d
fi
if grep -q "CONFIG_SYSLOGD=y" $BUILD_DIR/busybox-1.34.0/.config; then
	mkdir -pv $ROOTFS_DIR/etc/init.d
	cat >$ROOTFS_DIR/etc/init.d/S01logging <<"EOF"
#!/bin/sh
#
# Start logging
#
SYSLOGD_ARGS=-n
KLOGD_ARGS=-n
[ -r /etc/default/logging ] && . /etc/default/logging
start() {
	printf "Starting logging: "
	start-stop-daemon -b -S -q -m -p /var/run/syslogd.pid --exec /sbin/syslogd -- $SYSLOGD_ARGS
	start-stop-daemon -b -S -q -m -p /var/run/klogd.pid --exec /sbin/klogd -- $KLOGD_ARGS
	echo "OK"
}
stop() {
	printf "Stopping logging: "
	start-stop-daemon -K -q -p /var/run/syslogd.pid
	start-stop-daemon -K -q -p /var/run/klogd.pid
	echo "OK"
}
case "$1" in
  start)
	start
	;;
  stop)
	stop
	;;
  restart|reload)
	stop
	start
	;;
  *)
	echo "Usage: $0 {start|stop|restart}"
	exit 1
esac
exit $?
EOF
	chmod -v 0755 $ROOTFS_DIR/etc/init.d/S01logging
fi
cp -v $BUILD_DIR/busybox-1.34.0/examples/depmod.pl $TOOLS_DIR/bin/depmod.pl
rm -rf $BUILD_DIR/busybox-1.34.0

step "[7/22] Install Bootscript"
mkdir -pv $ROOTFS_DIR/etc/init.d
cat >$ROOTFS_DIR/etc/inittab <<"EOF"
# /etc/inittab
#
# Copyright (C) 2001 Erik Andersen <andersen@codepoet.org>
#
# Note: BusyBox init doesn't support runlevels.  The runlevels field is
# completely ignored by BusyBox init. If you want runlevels, use
# sysvinit.
#
# Format for each entry: <id>:<runlevels>:<action>:<process>
#
# id        == tty to run on, or empty for /dev/console
# runlevels == ignored
# action    == one of sysinit, respawn, askfirst, wait, and once
# process   == program to run
# Startup the system
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -o remount,rw /
::sysinit:/bin/mkdir -p /dev/pts /dev/shm
::sysinit:/bin/mount -a
::sysinit:/sbin/swapon -a
::sysinit:/bin/touch /var/log/btmp
::sysinit:/bin/touch /var/log/lastlog
::sysinit:/bin/touch /var/log/faillog
null::sysinit:/bin/ln -sf /proc/self/fd /dev/fd
null::sysinit:/bin/ln -sf /proc/self/fd/0 /dev/stdin
null::sysinit:/bin/ln -sf /proc/self/fd/1 /dev/stdout
null::sysinit:/bin/ln -sf /proc/self/fd/2 /dev/stderr
::sysinit:/bin/hostname -F /etc/hostname
# now run any rc scripts
::sysinit:/etc/init.d/rcS
# Stuff to do for the 3-finger salute
#::ctrlaltdel:/sbin/reboot
# Stuff to do before rebooting
::shutdown:/etc/init.d/rcK
::shutdown:/sbin/swapoff -a
::shutdown:/bin/umount -a -r
EOF
cat >$ROOTFS_DIR/etc/init.d/rcK <<"EOF"
#!/bin/sh
# Stop all init scripts in /etc/init.d
# executing them in reversed numerical order.
#
for i in $(ls -r /etc/init.d/S??*) ;do
     # Ignore dangling symlinks (if any).
     [ ! -f "$i" ] && continue
     case "$i" in
	*.sh)
	    # Source shell script for speed.
	    (
		trap - INT QUIT TSTP
		set stop
		. $i
	    )
	    ;;
	*)
	    # No sh extension, so fork subprocess.
	    $i stop
	    ;;
    esac
done
EOF
cat >$ROOTFS_DIR/etc/init.d/rcS <<"EOF"
#!/bin/sh
# Start all init scripts in /etc/init.d
# executing them in numerical order.
#
for i in /etc/init.d/S??* ;do
     # Ignore dangling symlinks (if any).
     [ ! -f "$i" ] && continue
     case "$i" in
	*.sh)
	    # Source shell script for speed.
	    (
		trap - INT QUIT TSTP
		set start
		. $i
	    )
	    ;;
	*)
	    # No sh extension, so fork subprocess.
	    $i start
	    ;;
    esac
done
EOF
cat >$ROOTFS_DIR/etc/init.d/S20urandom <<"EOF"
#! /bin/sh
#
# urandom	This script saves the random seed between reboots.
#		It is called from the boot, halt and reboot scripts.
#
# Version:	@(#)urandom  1.33  22-Jun-1998  miquels@cistron.nl
#
[ -c /dev/urandom ] || exit 0
#. /etc/default/rcS
case "$1" in
	start|"")
		# check for read only file system
		if ! touch /etc/random-seed 2>/dev/null
		then
			echo "read-only file system detected...done"
			exit
		fi
		if [ "$VERBOSE" != no ]
		then
			printf "Initializing random number generator... "
		fi
		# Load and then save 512 bytes,
		# which is the size of the entropy pool
		cat /etc/random-seed >/dev/urandom
		rm -f /etc/random-seed
		umask 077
		dd if=/dev/urandom of=/etc/random-seed count=1 \
			>/dev/null 2>&1 || echo "urandom start: failed."
		umask 022
		[ "$VERBOSE" != no ] && echo "done."
		;;
	stop)
		if ! touch /etc/random-seed 2>/dev/null
                then
                        exit
                fi
		# Carry a random seed from shut-down to start-up;
		# see documentation in linux/drivers/char/random.c
		[ "$VERBOSE" != no ] && printf "Saving random seed... "
		umask 077
		dd if=/dev/urandom of=/etc/random-seed count=1 \
			>/dev/null 2>&1 || echo "urandom stop: failed."
		[ "$VERBOSE" != no ] && echo "done."
		;;
	*)
		echo "Usage: urandom {start|stop}" >&2
		exit 1
		;;
esac
EOF
chmod -v 0755 $ROOTFS_DIR/etc/init.d/{rcK,rcS,S20urandom}

step "[8/22] General Network Configuration"
cat >$ROOTFS_DIR/etc/network/interfaces <<"EOF"
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
  pre-up /etc/network/nfs_check
  wait-delay 15
EOF
cat >$ROOTFS_DIR/etc/network/nfs_check <<"EOF"
#!/bin/sh
# This allows NFS booting to work while also being able to configure
# the network interface via DHCP when not NFS booting.  Otherwise, a
# NFS booted system will likely hang during DHCP configuration.
# Attempting to configure the network interface used for NFS will
# initially bring that network down.  Since the root filesystem is
# accessed over this network, the system hangs.
# This script is run by ifup and will attempt to detect if a NFS root
# mount uses the interface to be configured (IFACE), and if so does
# not configure it.  This should allow the same build to be disk/flash
# booted or NFS booted.
nfsip=`sed -n '/^[^ ]*:.* \/ nfs.*[ ,]addr=\([0-9.]\+\).*/s//\1/p' /proc/mounts`
if [ -n "$nfsip" ] && ip route get to "$nfsip" | grep -q "dev $IFACE"; then
	echo Skipping $IFACE, used for NFS from $nfsip
	exit 1
fi
EOF
chmod -v 0755 $ROOTFS_DIR/etc/network/nfs_check
cat >$ROOTFS_DIR/etc/network/if-pre-up.d/wait_iface <<"EOF"
#!/bin/sh
# In case we have a slow-to-appear interface (e.g. eth-over-USB),
# and we need to configure it, wait until it appears, but not too
# long either. IF_WAIT_DELAY is in seconds.
if [ "${IF_WAIT_DELAY}" -a ! -e "/sys/class/net/${IFACE}" ]; then
    printf "Waiting for interface %s to appear" "${IFACE}"
    while [ ${IF_WAIT_DELAY} -gt 0 ]; do
        if [ -e "/sys/class/net/${IFACE}" ]; then
            printf "\n"
            exit 0
        fi
        sleep 1
        printf "."
        : $((IF_WAIT_DELAY -= 1))
    done
    printf " timeout!\n"
    exit 1
fi
EOF
chmod -v 0755 $ROOTFS_DIR/etc/network/if-pre-up.d/wait_iface
echo "127.0.0.1	${CONFIG_HOSTNAME}" >$ROOTFS_DIR/etc/hosts
echo "${CONFIG_HOSTNAME}" >$ROOTFS_DIR/etc/hostname
cat >$ROOTFS_DIR/etc/protocols <<"EOF"
# Internet (IP) protocols
#
# Updated from http://www.iana.org/assignments/protocol-numbers and other
# sources.
ip	0	IP		# internet protocol, pseudo protocol number
hopopt	0	HOPOPT		# IPv6 Hop-by-Hop Option [RFC1883]
icmp	1	ICMP		# internet control message protocol
igmp	2	IGMP		# Internet Group Management
ggp	3	GGP		# gateway-gateway protocol
ipencap	4	IP-ENCAP	# IP encapsulated in IP (officially ``IP'')
st	5	ST		# ST datagram mode
tcp	6	TCP		# transmission control protocol
egp	8	EGP		# exterior gateway protocol
igp	9	IGP		# any private interior gateway (Cisco)
pup	12	PUP		# PARC universal packet protocol
udp	17	UDP		# user datagram protocol
hmp	20	HMP		# host monitoring protocol
xns-idp	22	XNS-IDP		# Xerox NS IDP
rdp	27	RDP		# "reliable datagram" protocol
iso-tp4	29	ISO-TP4		# ISO Transport Protocol class 4 [RFC905]
dccp	33	DCCP		# Datagram Congestion Control Prot. [RFC4340]
xtp	36	XTP		# Xpress Transfer Protocol
ddp	37	DDP		# Datagram Delivery Protocol
idpr-cmtp 38	IDPR-CMTP	# IDPR Control Message Transport
ipv6	41	IPv6		# Internet Protocol, version 6
ipv6-route 43	IPv6-Route	# Routing Header for IPv6
ipv6-frag 44	IPv6-Frag	# Fragment Header for IPv6
idrp	45	IDRP		# Inter-Domain Routing Protocol
rsvp	46	RSVP		# Reservation Protocol
gre	47	GRE		# General Routing Encapsulation
esp	50	IPSEC-ESP	# Encap Security Payload [RFC2406]
ah	51	IPSEC-AH	# Authentication Header [RFC2402]
skip	57	SKIP		# SKIP
ipv6-icmp 58	IPv6-ICMP	# ICMP for IPv6
ipv6-nonxt 59	IPv6-NoNxt	# No Next Header for IPv6
ipv6-opts 60	IPv6-Opts	# Destination Options for IPv6
rspf	73	RSPF CPHB	# Radio Shortest Path First (officially CPHB)
vmtp	81	VMTP		# Versatile Message Transport
eigrp	88	EIGRP		# Enhanced Interior Routing Protocol (Cisco)
ospf	89	OSPFIGP		# Open Shortest Path First IGP
ax.25	93	AX.25		# AX.25 frames
ipip	94	IPIP		# IP-within-IP Encapsulation Protocol
etherip	97	ETHERIP		# Ethernet-within-IP Encapsulation [RFC3378]
encap	98	ENCAP		# Yet Another IP encapsulation [RFC1241]
#	99			# any private encryption scheme
pim	103	PIM		# Protocol Independent Multicast
ipcomp	108	IPCOMP		# IP Payload Compression Protocol
vrrp	112	VRRP		# Virtual Router Redundancy Protocol [RFC5798]
l2tp	115	L2TP		# Layer Two Tunneling Protocol [RFC2661]
isis	124	ISIS		# IS-IS over IPv4
sctp	132	SCTP		# Stream Control Transmission Protocol
fc	133	FC		# Fibre Channel
mobility-header 135 Mobility-Header # Mobility Support for IPv6 [RFC3775]
udplite	136	UDPLite		# UDP-Lite [RFC3828]
mpls-in-ip 137	MPLS-in-IP	# MPLS-in-IP [RFC4023]
manet	138			# MANET Protocols [RFC5498]
hip	139	HIP		# Host Identity Protocol
shim6	140	Shim6		# Shim6 Protocol [RFC5533]
wesp	141	WESP		# Wrapped Encapsulating Security Payload
rohc	142	ROHC		# Robust Header Compression
EOF
cat >$ROOTFS_DIR/etc/protocols <<"EOF"
# /etc/services:
# $Id: services,v 1.1 2004/10/09 02:49:18 andersen Exp $
#
# Network services, Internet style
#
# Note that it is presently the policy of IANA to assign a single well-known
# port number for both TCP and UDP; hence, most entries here have two entries
# even if the protocol doesn't support UDP operations.
# Updated from RFC 1700, ``Assigned Numbers'' (October 1994).  Not all ports
# are included, only the more common ones.
tcpmux		1/tcp				# TCP port service multiplexer
echo		7/tcp
echo		7/udp
discard		9/tcp		sink null
discard		9/udp		sink null
systat		11/tcp		users
daytime		13/tcp
daytime		13/udp
netstat		15/tcp
qotd		17/tcp		quote
msp		18/tcp				# message send protocol
msp		18/udp				# message send protocol
chargen		19/tcp		ttytst source
chargen		19/udp		ttytst source
ftp-data	20/tcp
ftp		21/tcp
fsp		21/udp		fspd
ssh		22/tcp				# SSH Remote Login Protocol
ssh		22/udp				# SSH Remote Login Protocol
telnet		23/tcp
# 24 - private
smtp		25/tcp		mail
# 26 - unassigned
time		37/tcp		timserver
time		37/udp		timserver
rlp		39/udp		resource	# resource location
nameserver	42/tcp		name		# IEN 116
whois		43/tcp		nicname
re-mail-ck	50/tcp				# Remote Mail Checking Protocol
re-mail-ck	50/udp				# Remote Mail Checking Protocol
domain		53/tcp		nameserver	# name-domain server
domain		53/udp		nameserver
mtp		57/tcp				# deprecated
bootps		67/tcp				# BOOTP server
bootps		67/udp
bootpc		68/tcp				# BOOTP client
bootpc		68/udp
tftp		69/udp
gopher		70/tcp				# Internet Gopher
gopher		70/udp
rje		77/tcp		netrjs
finger		79/tcp
www		80/tcp		http		# WorldWideWeb HTTP
www		80/udp				# HyperText Transfer Protocol
link		87/tcp		ttylink
kerberos	88/tcp		kerberos5 krb5	# Kerberos v5
kerberos	88/udp		kerberos5 krb5	# Kerberos v5
supdup		95/tcp
# 100 - reserved
hostnames	101/tcp		hostname	# usually from sri-nic
iso-tsap	102/tcp		tsap		# part of ISODE.
csnet-ns	105/tcp		cso-ns		# also used by CSO name server
csnet-ns	105/udp		cso-ns
# unfortunately the poppassd (Eudora) uses a port which has already
# been assigned to a different service. We list the poppassd as an
# alias here. This should work for programs asking for this service.
# (due to a bug in inetd the 3com-tsmux line is disabled)
#3com-tsmux	106/tcp		poppassd
#3com-tsmux	106/udp		poppassd
rtelnet		107/tcp				# Remote Telnet
rtelnet		107/udp
pop-2		109/tcp		postoffice	# POP version 2
pop-2		109/udp
pop-3		110/tcp				# POP version 3
pop-3		110/udp
sunrpc		111/tcp		portmapper	# RPC 4.0 portmapper TCP
sunrpc		111/udp		portmapper	# RPC 4.0 portmapper UDP
auth		113/tcp		authentication tap ident
sftp		115/tcp
uucp-path	117/tcp
nntp		119/tcp		readnews untp	# USENET News Transfer Protocol
ntp		123/tcp
ntp		123/udp				# Network Time Protocol
netbios-ns	137/tcp				# NETBIOS Name Service
netbios-ns	137/udp
netbios-dgm	138/tcp				# NETBIOS Datagram Service
netbios-dgm	138/udp
netbios-ssn	139/tcp				# NETBIOS session service
netbios-ssn	139/udp
imap2		143/tcp				# Interim Mail Access Proto v2
imap2		143/udp
snmp		161/udp				# Simple Net Mgmt Proto
snmp-trap	162/udp		snmptrap	# Traps for SNMP
cmip-man	163/tcp				# ISO mgmt over IP (CMOT)
cmip-man	163/udp
cmip-agent	164/tcp
cmip-agent	164/udp
xdmcp		177/tcp				# X Display Mgr. Control Proto
xdmcp		177/udp
nextstep	178/tcp		NeXTStep NextStep	# NeXTStep window
nextstep	178/udp		NeXTStep NextStep	# server
bgp		179/tcp				# Border Gateway Proto.
bgp		179/udp
prospero	191/tcp				# Cliff Neuman's Prospero
prospero	191/udp
irc		194/tcp				# Internet Relay Chat
irc		194/udp
smux		199/tcp				# SNMP Unix Multiplexer
smux		199/udp
at-rtmp		201/tcp				# AppleTalk routing
at-rtmp		201/udp
at-nbp		202/tcp				# AppleTalk name binding
at-nbp		202/udp
at-echo		204/tcp				# AppleTalk echo
at-echo		204/udp
at-zis		206/tcp				# AppleTalk zone information
at-zis		206/udp
qmtp		209/tcp				# The Quick Mail Transfer Protocol
qmtp		209/udp				# The Quick Mail Transfer Protocol
z3950		210/tcp		wais		# NISO Z39.50 database
z3950		210/udp		wais
ipx		213/tcp				# IPX
ipx		213/udp
imap3		220/tcp				# Interactive Mail Access
imap3		220/udp				# Protocol v3
ulistserv	372/tcp				# UNIX Listserv
ulistserv	372/udp
https		443/tcp				# MCom
https		443/udp				# MCom
snpp		444/tcp				# Simple Network Paging Protocol
snpp		444/udp				# Simple Network Paging Protocol
saft		487/tcp				# Simple Asynchronous File Transfer
saft		487/udp				# Simple Asynchronous File Transfer
npmp-local	610/tcp		dqs313_qmaster	# npmp-local / DQS
npmp-local	610/udp		dqs313_qmaster	# npmp-local / DQS
npmp-gui	611/tcp		dqs313_execd	# npmp-gui / DQS
npmp-gui	611/udp		dqs313_execd	# npmp-gui / DQS
hmmp-ind	612/tcp		dqs313_intercell# HMMP Indication / DQS
hmmp-ind	612/udp		dqs313_intercell# HMMP Indication / DQS
#
# UNIX specific services
#
exec		512/tcp
biff		512/udp		comsat
login		513/tcp
who		513/udp		whod
shell		514/tcp		cmd		# no passwords used
syslog		514/udp
printer		515/tcp		spooler		# line printer spooler
talk		517/udp
ntalk		518/udp
route		520/udp		router routed	# RIP
timed		525/udp		timeserver
tempo		526/tcp		newdate
courier		530/tcp		rpc
conference	531/tcp		chat
netnews		532/tcp		readnews
netwall		533/udp				# -for emergency broadcasts
uucp		540/tcp		uucpd		# uucp daemon
afpovertcp	548/tcp				# AFP over TCP
afpovertcp	548/udp				# AFP over TCP
remotefs	556/tcp		rfs_server rfs	# Brunhoff remote filesystem
klogin		543/tcp				# Kerberized `rlogin' (v5)
kshell		544/tcp		krcmd		# Kerberized `rsh' (v5)
kerberos-adm	749/tcp				# Kerberos `kadmin' (v5)
#
webster		765/tcp				# Network dictionary
webster		765/udp
#
# From ``Assigned Numbers'':
#
#> The Registered Ports are not controlled by the IANA and on most systems
#> can be used by ordinary user processes or programs executed by ordinary
#> users.
#
#> Ports are used in the TCP [45,106] to name the ends of logical
#> connections which carry long term conversations.  For the purpose of
#> providing services to unknown callers, a service contact port is
#> defined.  This list specifies the port used by the server process as its
#> contact port.  While the IANA can not control uses of these ports it
#> does register or list uses of these ports as a convienence to the
#> community.
#
nfsdstatus	1110/tcp
nfsd-keepalive	1110/udp
ingreslock	1524/tcp
ingreslock	1524/udp
prospero-np	1525/tcp			# Prospero non-privileged
prospero-np	1525/udp
datametrics	1645/tcp	old-radius	# datametrics / old radius entry
datametrics	1645/udp	old-radius	# datametrics / old radius entry
sa-msg-port	1646/tcp	old-radacct	# sa-msg-port / old radacct entry
sa-msg-port	1646/udp	old-radacct	# sa-msg-port / old radacct entry
radius		1812/tcp			# Radius
radius		1812/udp			# Radius
radacct		1813/tcp			# Radius Accounting
radacct		1813/udp			# Radius Accounting
nfsd		2049/tcp	nfs
nfsd		2049/udp	nfs
cvspserver	2401/tcp			# CVS client/server operations
cvspserver	2401/udp			# CVS client/server operations
mysql		3306/tcp			# MySQL
mysql		3306/udp			# MySQL
rfe		5002/tcp			# Radio Free Ethernet
rfe		5002/udp			# Actually uses UDP only
cfengine	5308/tcp			# CFengine
cfengine	5308/udp			# CFengine
bbs		7000/tcp			# BBS service
#
#
# Kerberos (Project Athena/MIT) services
# Note that these are for Kerberos v4, and are unofficial.  Sites running
# v4 should uncomment these and comment out the v5 entries above.
#
kerberos4	750/udp		kerberos-iv kdc	# Kerberos (server) udp
kerberos4	750/tcp		kerberos-iv kdc	# Kerberos (server) tcp
kerberos_master	751/udp				# Kerberos authentication
kerberos_master	751/tcp				# Kerberos authentication
passwd_server	752/udp				# Kerberos passwd server
krb_prop	754/tcp				# Kerberos slave propagation
krbupdate	760/tcp		kreg		# Kerberos registration
kpasswd		761/tcp		kpwd		# Kerberos "passwd"
kpop		1109/tcp			# Pop with Kerberos
knetd		2053/tcp			# Kerberos de-multiplexor
zephyr-srv	2102/udp			# Zephyr server
zephyr-clt	2103/udp			# Zephyr serv-hm connection
zephyr-hm	2104/udp			# Zephyr hostmanager
eklogin		2105/tcp			# Kerberos encrypted rlogin
#
# Unofficial but necessary (for NetBSD) services
#
supfilesrv	871/tcp				# SUP server
supfiledbg	1127/tcp			# SUP debugging
#
# Datagram Delivery Protocol services
#
rtmp		1/ddp				# Routing Table Maintenance Protocol
nbp		2/ddp				# Name Binding Protocol
echo		4/ddp				# AppleTalk Echo Protocol
zip		6/ddp				# Zone Information Protocol
#
# Services added for the Debian GNU/Linux distribution
poppassd	106/tcp				# Eudora
poppassd	106/udp				# Eudora
mailq		174/tcp				# Mailer transport queue for Zmailer
mailq		174/tcp				# Mailer transport queue for Zmailer
omirr		808/tcp		omirrd		# online mirror
omirr		808/udp		omirrd		# online mirror
rmtcfg		1236/tcp			# Gracilis Packeten remote config server
xtel		1313/tcp			# french minitel
coda_opcons	1355/udp			# Coda opcons            (Coda fs)
coda_venus	1363/udp			# Coda venus             (Coda fs)
coda_auth	1357/udp			# Coda auth              (Coda fs)
coda_udpsrv	1359/udp			# Coda udpsrv            (Coda fs)
coda_filesrv	1361/udp			# Coda filesrv           (Coda fs)
codacon		1423/tcp	venus.cmu	# Coda Console           (Coda fs)
coda_aux1	1431/tcp			# coda auxiliary service (Coda fs)
coda_aux1	1431/udp			# coda auxiliary service (Coda fs)
coda_aux2	1433/tcp			# coda auxiliary service (Coda fs)
coda_aux2	1433/udp			# coda auxiliary service (Coda fs)
coda_aux3	1435/tcp			# coda auxiliary service (Coda fs)
coda_aux3	1435/udp			# coda auxiliary service (Coda fs)
cfinger		2003/tcp			# GNU Finger
afbackup	2988/tcp			# Afbackup system
afbackup	2988/udp			# Afbackup system
icp		3130/tcp			# Internet Cache Protocol (Squid)
icp		3130/udp			# Internet Cache Protocol (Squid)
postgres	5432/tcp			# POSTGRES
postgres	5432/udp			# POSTGRES
fax		4557/tcp			# FAX transmission service        (old)
hylafax		4559/tcp			# HylaFAX client-server protocol  (new)
noclog		5354/tcp			# noclogd with TCP (nocol)
noclog		5354/udp			# noclogd with UDP (nocol)
hostmon		5355/tcp			# hostmon uses TCP (nocol)
hostmon		5355/udp			# hostmon uses TCP (nocol)
ircd		6667/tcp			# Internet Relay Chat
ircd		6667/udp			# Internet Relay Chat
webcache	8080/tcp			# WWW caching service
webcache	8080/udp			# WWW caching service
tproxy		8081/tcp			# Transparent Proxy
tproxy		8081/udp			# Transparent Proxy
mandelspawn	9359/udp	mandelbrot	# network mandelbrot
amanda		10080/udp			# amanda backup services
amandaidx	10082/tcp			# amanda backup services
amidxtape	10083/tcp			# amanda backup services
isdnlog		20011/tcp			# isdn logging system
isdnlog		20011/udp			# isdn logging system
vboxd		20012/tcp			# voice box system
vboxd		20012/udp			# voice box system
binkp           24554/tcp			# Binkley
binkp           24554/udp			# Binkley
asp		27374/tcp			# Address Search Protocol
asp		27374/udp			# Address Search Protocol
tfido           60177/tcp			# Ifmail
tfido           60177/udp			# Ifmail
fido            60179/tcp			# Ifmail
fido            60179/udp			# Ifmail
# Local services
EOF

step "[9/22] The Bash Shell Startup Files"
cat >$ROOTFS_DIR/etc/profile <<"EOF"
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
if [ "$PS1" ]; then
	if [ "`id -u`" -eq 0 ]; then
		export PS1="\[\033[m\]|\[\033[1;35m\]\t\[\033[m\]|\[\e[1m\]\u\[\e[1;36m\]\[\033[m\]@\[\e[1;36m\]\h\[\033[m\]:\[\e[0m\]\[\e[1;32m\][\w]> \[\e[0m\]"
	else
		export PS1="\[\033[m\]|\[\033[1;35m\]\t\[\033[m\]|\[\e[1m\]\u\[\e[1;36m\]\[\033[m\]@\[\e[1;36m\]\h\[\033[m\]:\[\e[0m\]\[\e[1;32m\][\w]> \[\e[0m\]"
	fi
fi
export PAGER='/bin/more'
export EDITOR='/bin/vi'
# Source configuration files from /etc/profile.d
for i in /etc/profile.d/*.sh ; do
	if [ -r "$i" ]; then
		. $i
	fi
done
unset i
EOF
echo "umask 022" >$ROOTFS_DIR/etc/profile.d/umask.sh

step "[10/22] Creating the /etc/fstab File"
cat >$ROOTFS_DIR/etc/fstab <<"EOF"
# <file system>	<mount pt>	<type>	<options>	<dump>	<pass>
/dev/root	/		ext2	rw,noauto	0	1
proc		/proc		proc	defaults	0	0
devpts		/dev/pts	devpts	defaults,gid=5,mode=620,ptmxmode=0666	0	0
tmpfs		/dev/shm	tmpfs	mode=0777	0	0
tmpfs		/tmp		tmpfs	mode=1777	0	0
tmpfs		/run		tmpfs	mode=0755,nosuid,nodev	0	0
sysfs		/sys		sysfs	defaults	0	0
EOF

step "[11/22] Setting Local Timezone"
mkdir $BUILD_DIR/tzdata2021a
extract $SOURCES_DIR/tzdata2021a.tar.gz $BUILD_DIR/tzdata2021a
ZONEINFO=$ROOTFS_DIR/usr/share/zoneinfo
mkdir -pv $ZONEINFO/{posix,right}
(cd $BUILD_DIR/tzdata2021a &&
	for tz in etcetera southamerica northamerica europe africa antarctica asia australasia backward; do
		zic -L /dev/null -d $ZONEINFO ${tz}
		zic -L /dev/null -d $ZONEINFO/posix ${tz}
		zic -L leapseconds -d $ZONEINFO/right ${tz}
	done)
cp -v $BUILD_DIR/tzdata2021a/{zone.tab,zone1970.tab,iso3166.tab} $ZONEINFO
ln -sfv /usr/share/zoneinfo/$CONFIG_LOCAL_TIMEZONE $ROOTFS_DIR/etc/localtime
echo "$CONFIG_LOCAL_TIMEZONE" >$ROOTFS_DIR//etc/timezone
rm -rf $BUILD_DIR/tzdata2021a

step "[12/22] Zlib 1.2.11"
extract $SOURCES_DIR/zlib-1.2.11.tar.xz $BUILD_DIR
(cd $BUILD_DIR/zlib-1.2.11 && CC=$TOOLS_DIR/usr/bin/$CONFIG_TARGET-gcc ./configure --shared --prefix=/usr)
make -j1 -C $BUILD_DIR/zlib-1.2.11
make -j1 DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/zlib-1.2.11
make -j1 DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/zlib-1.2.11
rm -rf $BUILD_DIR/zlib-1.2.11

step "[13/22] OpenSSL 1.1.1d"
extract $SOURCES_DIR/openssl-1.1.1d.tar.gz $BUILD_DIR
(cd $BUILD_DIR/openssl-1.1.1d &&
	./Configure \
		linux-x86_64 \
		--prefix=/usr \
		--openssldir=/etc/ssl \
		--libdir=/lib \
		shared \
		zlib-dynamic)
sed -i -e "s# build_tests##" $BUILD_DIR/openssl-1.1.1d/Makefile
make -j1 -C $BUILD_DIR/openssl-1.1.1d
make -j1 DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/openssl-1.1.1d
make -j1 DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/openssl-1.1.1d
rm -rf $BUILD_DIR/openssl-1.1.1d

step "[14/22] Curl 7.79.0"
extract $SOURCES_DIR/curl-7.79.0.tar.xz $BUILD_DIR
(cd $BUILD_DIR/curl-7.79.0 &&
	./configure \
		--target=$CONFIG_TARGET \
		--host=$CONFIG_TARGET \
		--build=$CONFIG_HOST \
		--prefix=/usr \
		--disable-static \
		--with-openssl \
		--enable-threaded-resolver \
		--with-ca-path=/etc/ssl/certs)
make -j$PARALLEL_JOBS -C $BUILD_DIR/curl-7.79.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/curl-7.79.0
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/curl-7.79.0
rm -rf $BUILD_DIR/curl-7.79.0

step "[15/22] OpenSSH 8.7p1"
extract $SOURCES_DIR/openssh-8.7p1.tar.gz $BUILD_DIR
(cd $BUILD_DIR/openssh-8.7p1 &&
	./configure \
		--target=$CONFIG_TARGET \
		--host=$CONFIG_TARGET \
		--build=$CONFIG_HOST \
		--prefix=/usr \
		--sysconfdir=/etc/ssh \
		--with-md5-passwords \
		--with-privsep-path=/var/lib/sshd \
		--with-default-path=/usr/bin \
		--with-superuser-path=/usr/sbin:/usr/bin \
		--with-pid-dir=/run \
		--disable-strip \
		--disable-utmp \
		--disable-utmpx \
		--disable-wtmp \
		--disable-wtmpx)
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssh-8.7p1
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/openssh-8.7p1
install -v -m700 -d $ROOTFS_DIR/var/lib/sshd
install -v -m755 $BUILD_DIR/openssh-8.7p1/contrib/ssh-copy-id $ROOTFS_DIR/usr/bin
echo 'sshd:x:50:50:sshd PrivSep:/var/lib/sshd:/bin/false' >>$ROOTFS_DIR/etc/passwd
echo 'sshd:x:50:' >>$ROOTFS_DIR/etc/group
echo "PermitRootLogin yes" >>$ROOTFS_DIR/etc/ssh/sshd_config
echo "PasswordAuthentication yes" >>$ROOTFS_DIR/etc/ssh/sshd_config
echo "ListenAddress 0.0.0.0" >>$ROOTFS_DIR/etc/ssh/sshd_config
install -m 754 $SUPPORT_DIR/openssh/sshd $ROOTFS_DIR/etc/init.d/S50sshd
rm -rf $BUILD_DIR/openssh-8.7p1

step "[16/22] Which 2.21"
extract $SOURCES_DIR/which-2.21.tar.gz $BUILD_DIR
(cd $BUILD_DIR/which-2.21 &&
	./configure \
		--target=$CONFIG_TARGET \
		--host=$CONFIG_TARGET \
		--build=$CONFIG_HOST \
		--prefix=/usr)
make -j$PARALLEL_JOBS -C $BUILD_DIR/which-2.21
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/which-2.21
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/which-2.21
rm -rf $BUILD_DIR/which-2.21

step "[17/22] libuv 1.42.0"
extract $SOURCES_DIR/libuv-v1.42.0.tar.gz $BUILD_DIR
(cd $BUILD_DIR/libuv-v1.42.0 && sh autogen.sh)
(cd $BUILD_DIR/libuv-v1.42.0 &&
	./configure \
		--target=$CONFIG_TARGET \
		--host=$CONFIG_TARGET \
		--build=$CONFIG_HOST \
		--prefix=/usr \
		--disable-static)
make -j$PARALLEL_JOBS -C $BUILD_DIR/libuv-v1.42.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/libuv-v1.42.0
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/libuv-v1.42.0
rm -rf $BUILD_DIR/libuv-v1.42.0

step "[18/22] nghttp2 1.44.0"
extract $SOURCES_DIR/nghttp2-1.44.0.tar.xz $BUILD_DIR
(cd $BUILD_DIR/nghttp2-1.44.0 &&
	./configure \
		--target=$CONFIG_TARGET \
		--host=$CONFIG_TARGET \
		--build=$CONFIG_HOST \
		--prefix=/usr \
		--disable-static \
		--enable-lib-only \
		--docdir=/usr/share/doc/nghttp2-1.44.0)
make -j$PARALLEL_JOBS -C $BUILD_DIR/nghttp2-1.44.0
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/nghttp2-1.44.0
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/nghttp2-1.44.0
rm -rf $BUILD_DIR/nghttp2-1.44.0

step "[19/22] Node.js 14.17.6"
extract $SOURCES_DIR/node-v14.17.6.tar.xz $BUILD_DIR
sed -i 's|ares_nameser.h|arpa/nameser.h|' $BUILD_DIR/node-v14.17.6/src/cares_wrap.h
(cd $BUILD_DIR/node-v14.17.6 &&
	CC_host="gcc" \
		CXX_host="g++" \
		AR_host="ar" \
		AS_host="as" \
		LINK_host="g++ -O2 -I$TOOLS_DIR/include -L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib" \
		RANLIB_host="ranlib" \
		./configure \
		--without-dtrace \
		--without-etw \
		--cross-compiling \
		--without-snapshot \
		--dest-cpu=$CONFIG_LINUX_ARCH \
		--dest-os=linux \
		--prefix=/usr \
		--shared-libuv \
		--shared-openssl \
		--shared-nghttp2 \
		--shared-zlib \
		--with-intl=none)
make -j$PARALLEL_JOBS -C $BUILD_DIR/node-v14.17.6
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/node-v14.17.6
rm -rf $BUILD_DIR/node-v14.17.6

step "[20/22] Nginx 1.21.3"
extract $SOURCES_DIR/nginx-1.21.3.tar.gz $BUILD_DIR
(cd $BUILD_DIR/nginx-1.21.3 &&
	ngx_force_c99_have_variadic_macros=yes \
		ngx_force_c_compiler=yes \
		ngx_force_gcc_have_atomic=yes \
		ngx_force_gcc_have_variadic_macros=yes \
		ngx_force_have_epoll=yes \
		ngx_force_have_map_anon=yes \
		ngx_force_have_map_devzero=yes \
		ngx_force_have_posix_sem=yes \
		ngx_force_have_pr_set_dumpable=yes \
		ngx_force_have_sendfile64=yes \
		ngx_force_have_sendfile=yes \
		ngx_force_have_sysvshm=yes \
		ngx_force_have_timer_event=yes \
		./configure \
		--conf-path=/etc/nginx/nginx.conf \
		--crossbuild=Linux::$CONFIG_LINUX_ARCH \
		--error-log-path=/var/log/nginx/error.log \
		--group=www-data \
		--http-client-body-temp-path=/var/cache/nginx/client-body \
		--http-fastcgi-temp-path=/var/cache/nginx/fastcgi \
		--http-log-path=/var/log/nginx/access.log \
		--http-proxy-temp-path=/var/cache/nginx/proxy \
		--http-scgi-temp-path=/var/cache/nginx/scgi \
		--http-uwsgi-temp-path=/var/cache/nginx/uwsgi \
		--lock-path=/run/lock/nginx.lock \
		--pid-path=/run/nginx.pid \
		--prefix=/usr \
		--sbin-path=/usr/sbin/nginx \
		--user=www-data \
		--with-cc="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc" \
		--with-cpp="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc" \
		--without-pcre \
		--without-http_rewrite_module)
make -j$PARALLEL_JOBS -C $BUILD_DIR/nginx-1.21.3
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/nginx-1.21.3
sed -i 's/listen       80;/listen       8080;/g' $ROOTFS_DIR/etc/nginx/nginx.conf
install -m 755 $SUPPORT_DIR/nginx/nginx $ROOTFS_DIR/etc/init.d/S50nginx
rm -rf $BUILD_DIR/nginx-1.21.3

step "[21/22] Ncurses 6.2"
extract $SOURCES_DIR/ncurses-6.2.tar.gz $BUILD_DIR
(cd $BUILD_DIR/ncurses-6.2 &&
	./configure \
		--target=$CONFIG_TARGET \
		--host=$CONFIG_TARGET \
		--build=$CONFIG_HOST \
		--without-cxx \
		--without-cxx-binding \
		--without-ada \
		--without-tests \
		--disable-big-core \
		--without-profile \
		--disable-rpath \
		--disable-rpath-hack \
		--enable-echo \
		--enable-const \
		--enable-overwrite \
		--enable-pc-files \
		--disable-stripping \
		--with-pkg-config-libdir="/usr/lib/pkgconfig" \
		--without-progs \
		--without-manpages \
		--with-shared \
		--without-normal \
		--without-debug)
make -j$PARALLEL_JOBS -C $BUILD_DIR/ncurses-6.2
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/ncurses-6.2
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/ncurses-6.2
rm -rf $BUILD_DIR/ncurses-6.2

step "[22/22] MariaDB 10.6.4"
extract $SOURCES_DIR/mariadb-10.6.4.tar.gz $BUILD_DIR
mkdir $BUILD_DIR/mariadb-10.6.4/build
(
	cd $BUILD_DIR/mariadb-10.6.4/build &&
		cmake -DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_CROSSCOMPILING=1 \
			-DCMAKE_INSTALL_PREFIX=/usr \
			-DINSTALL_DOCDIR=share/doc/mariadb-10.6.4 \
			-DINSTALL_DOCREADMEDIR=share/doc/mariadb-10.6.4 \
			-DINSTALL_MANDIR=share/man \
			-DINSTALL_MYSQLSHAREDIR=share/mysql \
			-DINSTALL_MYSQLTESTDIR=share/mysql/test \
			-DINSTALL_PLUGINDIR=lib/mysql/plugin \
			-DINSTALL_SBINDIR=sbin \
			-DINSTALL_SCRIPTDIR=bin \
			-DINSTALL_SQLBENCHDIR=share/mysql/bench \
			-DINSTALL_SUPPORTFILESDIR=share/mysql \
			-DMYSQL_DATADIR=/srv/mysql \
			-DMYSQL_UNIX_ADDR=/run/mysqld/mysqld.sock \
			-DWITH_EXTRA_CHARSETS=complex \
			-DWITH_EMBEDDED_SERVER=ON \
			-DSKIP_TESTS=ON \
			-DWITH_UNIT_TESTS=0 \
			-DTOKUDB_OK=0 \
			-DWITHOUT_ROCKSDB=1 \
			..
)
sed -i -e "s@\./comp_err@$TOOLS_DIR/bin/comp_err@g" $BUILD_DIR/mariadb-10.6.4/build/extra/CMakeFiles/GenError.dir/build.make
sed -i -e "s@\./gen_lex_hash@$TOOLS_DIR/bin/gen_lex_hash@g" $BUILD_DIR/mariadb-10.6.4/build/sql/CMakeFiles/GenServerSource.dir/build.make
sed -i -e "s@\./gen_lex_token@$TOOLS_DIR/bin/gen_lex_token@g" $BUILD_DIR/mariadb-10.6.4/build/sql/CMakeFiles/GenServerSource.dir/build.make
sed -i -e "s@\./gen_lex_hash@$TOOLS_DIR/bin/gen_lex_hash@g" $BUILD_DIR/mariadb-10.6.4/build/sql/CMakeFiles/sql.dir/build.make
sed -i -e "s@\./gen_lex_token@$TOOLS_DIR/bin/gen_lex_token@g" $BUILD_DIR/mariadb-10.6.4/build/sql/CMakeFiles/sql.dir/build.make
sed -i -e "s@\./factorial@$TOOLS_DIR/bin/factorial@g" $BUILD_DIR/mariadb-10.6.4/build/dbug/CMakeFiles/user_t.dir/build.make
sed -i -e "s@\./factorial@$TOOLS_DIR/bin/factorial@g" $BUILD_DIR/mariadb-10.6.4/build/dbug/CMakeFiles/user_ps.dir/build.make
sed -i -e "s@$BUILD_DIR/mariadb-10.6.4/build/scripts/comp_sql@$TOOLS_DIR/bin/comp_sql@g" $BUILD_DIR/mariadb-10.6.4/build/scripts/CMakeFiles/GenFixPrivs.dir/build.make
make -j$PARALLEL_JOBS -C $BUILD_DIR/mariadb-10.6.4/build
make -j$PARALLEL_JOBS DESTDIR=$ROOTFS_DIR install -C $BUILD_DIR/mariadb-10.6.4/build
install -m 755 $SUPPORT_DIR/mariadb/mysqld $ROOTFS_DIR/etc/init.d/S97mysqld
mkdir -pv $ROOTFS_DIR/srv/mysql
echo 'mysql:x:40:40:MySQL Server:/srv/mysql:/bin/false' >>$ROOTFS_DIR/etc/passwd
rm -rf $BUILD_DIR/mariadb-10.6.4

success "\nTotal root file system build time: $(timer $total_build_time)\n"
