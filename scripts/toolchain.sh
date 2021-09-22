#!/bin/bash
#
# QNAS toolchain build script
# Optional parameteres below:
set +h
set -o nounset
set -o errexit
umask 022

export LC_ALL=POSIX
export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

export CFLAGS="-O2 -I$TOOLS_DIR/include"
export CPPFLAGS="-O2 -I$TOOLS_DIR/include"
export CXXFLAGS="-O2 -I$TOOLS_DIR/include"
export LDFLAGS="-L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib"

export PKG_CONFIG="$TOOLS_DIR/bin/pkg-config"
export PKG_CONFIG_SYSROOT_DIR="/"
export PKG_CONFIG_LIBDIR="$TOOLS_DIR/lib/pkgconfig:$TOOLS_DIR/share/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1

CONFIG_PKG_VERSION="QNAS AArch64 2021.09"
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
    if ! [[ -d $SOURCES_DIR ]] ; then
        error "Please download tarball files!"
        error "Run 'make download'."
        exit 1
    fi
}

function check_tarballs {
    LIST_OF_TARBALLS="
    "

    for tarball in $LIST_OF_TARBALLS ; do
        if ! [[ -f $SOURCES_DIR/$tarball ]] ; then
            error "Can't find '$tarball'!"
            exit 1
        fi
    done
}

function do_strip {
    set +o errexit
    if [[ $CONFIG_STRIP_AND_DELETE_DOCS = 1 ]] ; then
        strip --strip-debug $TOOLS_DIR/lib/*
        strip --strip-unneeded $TOOLS_DIR/{,s}bin/*
        rm -rf $TOOLS_DIR/{,share}/{info,man,doc}
    fi
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

step "[1/32] Create toolchain directory."
rm -rf $BUILD_DIR $TOOLS_DIR
mkdir -pv $BUILD_DIR $TOOLS_DIR
ln -svf . $TOOLS_DIR/usr

step "[2/32] Create the sysroot directory"
mkdir -pv $SYSROOT_DIR
ln -svf . $SYSROOT_DIR/usr
mkdir -pv $SYSROOT_DIR/lib
if [[ "$CONFIG_LINUX_ARCH" = "arm" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib32
fi
if [[ "$CONFIG_LINUX_ARCH" = "arm64" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib64
fi

step "[3/32] Pkgconf 1.8.0"
extract $SOURCES_DIR/pkgconf-1.8.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/pkgconf-1.8.0 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-dependency-tracking )
make -j$PARALLEL_JOBS -C $BUILD_DIR/pkgconf-1.8.0
make -j$PARALLEL_JOBS install -C $BUILD_DIR/pkgconf-1.8.0
cat > $TOOLS_DIR/bin/pkg-config << "EOF"
#!/bin/sh
PKGCONFDIR=$(dirname $0)
DEFAULT_PKG_CONFIG_LIBDIR=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/lib/pkgconfig:${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/share/pkgconfig
DEFAULT_PKG_CONFIG_SYSROOT_DIR=${PKGCONFDIR}/../@STAGING_SUBDIR@
DEFAULT_PKG_CONFIG_SYSTEM_INCLUDE_PATH=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/include
DEFAULT_PKG_CONFIG_SYSTEM_LIBRARY_PATH=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/lib
PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-${DEFAULT_PKG_CONFIG_LIBDIR}} \
	PKG_CONFIG_SYSROOT_DIR=${PKG_CONFIG_SYSROOT_DIR:-${DEFAULT_PKG_CONFIG_SYSROOT_DIR}} \
	PKG_CONFIG_SYSTEM_INCLUDE_PATH=${PKG_CONFIG_SYSTEM_INCLUDE_PATH:-${DEFAULT_PKG_CONFIG_SYSTEM_INCLUDE_PATH}} \
	PKG_CONFIG_SYSTEM_LIBRARY_PATH=${PKG_CONFIG_SYSTEM_LIBRARY_PATH:-${DEFAULT_PKG_CONFIG_SYSTEM_LIBRARY_PATH}} \
	exec ${PKGCONFDIR}/pkgconf @STATIC@ "$@"
EOF
chmod 755 $TOOLS_DIR/bin/pkg-config
sed -i -e "s,@STAGING_SUBDIR@,$SYSROOT_DIR,g" $TOOLS_DIR/bin/pkg-config
sed -i -e "s,@STATIC@,," $TOOLS_DIR/bin/pkg-config
rm -rf $BUILD_DIR/pkgconf-1.8.0

step "[4/32] M4 1.4.19"
extract $SOURCES_DIR/m4-1.4.19.tar.xz $BUILD_DIR
( cd $BUILD_DIR/m4-1.4.19 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/m4-1.4.19
make -j$PARALLEL_JOBS install -C $BUILD_DIR/m4-1.4.19
rm -rf $BUILD_DIR/m4-1.4.19

step "[5/32] Libtool 2.4.6"
extract $SOURCES_DIR/libtool-2.4.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/libtool-2.4.6 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libtool-2.4.6
make -j$PARALLEL_JOBS install -C $BUILD_DIR/libtool-2.4.6
rm -rf $BUILD_DIR/libtool-2.4.6

step "[6/32] Autoconf 2.71"
extract $SOURCES_DIR/autoconf-2.71.tar.xz $BUILD_DIR
( cd $BUILD_DIR/autoconf-2.71 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/autoconf-2.71
make -j$PARALLEL_JOBS install -C $BUILD_DIR/autoconf-2.71
rm -rf $BUILD_DIR/autoconf-2.71

step "[7/32] Automake 1.16.4"
extract $SOURCES_DIR/automake-1.16.4.tar.xz $BUILD_DIR
( cd $BUILD_DIR/automake-1.16.4 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/automake-1.16.4
make -j$PARALLEL_JOBS install -C $BUILD_DIR/automake-1.16.4
mkdir -p $SYSROOT_DIR/usr/share/aclocal
rm -rf $BUILD_DIR/automake-1.16.4

step "[8/32] Zlib 1.2.11"
extract $SOURCES_DIR/zlib-1.2.11.tar.xz $BUILD_DIR
( cd $BUILD_DIR/zlib-1.2.11 && ./configure --prefix=$TOOLS_DIR )
make -j1 -C $BUILD_DIR/zlib-1.2.11
make -j1 install -C $BUILD_DIR/zlib-1.2.11
rm -rf $BUILD_DIR/zlib-1.2.11

step "[9/32] Fakeroot 1.25.3"
extract $SOURCES_DIR/fakeroot_1.25.3.orig.tar.gz $BUILD_DIR
sed -i 's/doc//g' $BUILD_DIR/fakeroot-1.25.3/Makefile.am
( cd $BUILD_DIR/fakeroot-1.25.3 && autoreconf -i )
( cd $BUILD_DIR/fakeroot-1.25.3 && \
    MAKEINFO=true \
    ac_cv_header_sys_capability_h=no \
    ac_cv_func_capset=no \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/fakeroot-1.25.3
make -j$PARALLEL_JOBS install -C $BUILD_DIR/fakeroot-1.25.3
rm -rf $BUILD_DIR/fakeroot-1.25.3

step "[10/32] Bison 3.7.6"
extract $SOURCES_DIR/bison-3.7.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/bison-3.7.6 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bison-3.7.6
make -j$PARALLEL_JOBS install -C $BUILD_DIR/bison-3.7.6
rm -rf $BUILD_DIR/bison-3.7.6

step "[11/32] Gawk 5.1.0"
extract $SOURCES_DIR/gawk-5.1.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/gawk-5.1.0 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --without-readline \
    --without-mpfr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gawk-5.1.0
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gawk-5.1.0
rm -rf $BUILD_DIR/gawk-5.1.0

step "[12/32] Binutils 2.37"
extract $SOURCES_DIR/binutils-2.37.tar.xz $BUILD_DIR
mkdir -pv $BUILD_DIR/binutils-2.37/binutils-build
( cd $BUILD_DIR/binutils-2.37/binutils-build && \
    MAKEINFO=true \
    $BUILD_DIR/binutils-2.37/configure \
    --prefix=$TOOLS_DIR \
    --target=$CONFIG_TARGET \
    --disable-multilib \
    --disable-werror \
    --disable-shared \
    --enable-static \
    --with-sysroot=$SYSROOT_DIR \
    --enable-poison-system-directories \
    --disable-sim \
    --disable-gdb )
make -j$PARALLEL_JOBS configure-host -C $BUILD_DIR/binutils-2.37/binutils-build
make -j$PARALLEL_JOBS -C $BUILD_DIR/binutils-2.37/binutils-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/binutils-2.37/binutils-build
rm -rf $BUILD_DIR/binutils-2.37

step "[13/32] Gcc 11.2.0 - Static"
extract $SOURCES_DIR/gcc-11.2.0.tar.xz $BUILD_DIR
extract $SOURCES_DIR/gmp-6.2.1.tar.xz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/gmp-6.2.1 $BUILD_DIR/gcc-11.2.0/gmp
extract $SOURCES_DIR/mpfr-4.1.0.tar.xz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/mpfr-4.1.0 $BUILD_DIR/gcc-11.2.0/mpfr
extract $SOURCES_DIR/mpc-1.2.1.tar.gz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/mpc-1.2.1 $BUILD_DIR/gcc-11.2.0/mpc
mkdir -pv $BUILD_DIR/gcc-11.2.0/gcc-static-build
( cd $BUILD_DIR/gcc-11.2.0/gcc-static-build && \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    MAKEINFO=missing \
    $BUILD_DIR/gcc-11.2.0/configure \
    --build=$CONFIG_HOST \
    --disable-decimal-float \
    --disable-largefile \
    --disable-libquadmath \
    --disable-libssp \
    --disable-multilib \
    --disable-shared \
    --disable-static \
    --disable-threads \
    --enable-__cxa_atexit \
    --enable-languages=c \
    --enable-tls \
    --host=$CONFIG_HOST \
    --prefix=$TOOLS_DIR \
    --target=$CONFIG_TARGET \
    --with-abi="$CONFIG_GCC_ABI" \
    --with-bugurl="$CONFIG_BUG_URL" \
    --with-cpu="$CONFIG_GCC_CPU" \
    --with-gnu-ld \
    --with-newlib \
    --with-pkgversion="$CONFIG_PKG_VERSION" \
    --with-sysroot=$SYSROOT_DIR \
    --without-cloog \
    --without-headers \
    --without-isl )
make -j$PARALLEL_JOBS gcc_cv_libc_provides_ssp=yes all-gcc all-target-libgcc -C $BUILD_DIR/gcc-11.2.0/gcc-static-build
make -j$PARALLEL_JOBS install-gcc install-target-libgcc -C $BUILD_DIR/gcc-11.2.0/gcc-static-build
rm -rf $BUILD_DIR/gcc-11.2.0

step "[14/32] Linux 5.13.13 API Headers"
extract $SOURCES_DIR/linux-5.13.13.tar.xz $BUILD_DIR
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH mrproper -C $BUILD_DIR/linux-5.13.13
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH headers_check -C $BUILD_DIR/linux-5.13.13
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH INSTALL_HDR_PATH=$SYSROOT_DIR headers_install -C $BUILD_DIR/linux-5.13.13
rm -rf $BUILD_DIR/linux-5.13.13

step "[15/32] musl 1.2.2"
extract $SOURCES_DIR/musl-1.2.2.tar.gz $BUILD_DIR
sed -i 's@/dev/null/utmp@/var/log/utmp@g' $BUILD_DIR/musl-1.2.2/include/paths.h
sed -i 's@/dev/null/wtmp@/var/log/wtmp@g' $BUILD_DIR/musl-1.2.2/include/paths.h
mkdir $BUILD_DIR/musl-1.2.2/musl-build
( cd $BUILD_DIR/musl-1.2.2/musl-build && \
    $BUILD_DIR/musl-1.2.2/configure \
    CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" \
    --prefix=/usr \
    --target=$CONFIG_TARGET \
    --enable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/musl-1.2.2/musl-build
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/musl-1.2.2/musl-build
install -m 0644 -D $SUPPORT_DIR/musl/queue.h $SYSROOT_DIR/include/sys/queue.h
rm -rf $BUILD_DIR/musl-1.2.2

step "[16/32] Gcc 11.2.0 - Final"
extract $SOURCES_DIR/gcc-11.2.0.tar.xz $BUILD_DIR
extract $SOURCES_DIR/gmp-6.2.1.tar.xz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/gmp-6.2.1 $BUILD_DIR/gcc-11.2.0/gmp
extract $SOURCES_DIR/mpfr-4.1.0.tar.xz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/mpfr-4.1.0 $BUILD_DIR/gcc-11.2.0/mpfr
extract $SOURCES_DIR/mpc-1.2.1.tar.gz $BUILD_DIR/gcc-11.2.0
mv -v $BUILD_DIR/gcc-11.2.0/mpc-1.2.1 $BUILD_DIR/gcc-11.2.0/mpc
mkdir -v $BUILD_DIR/gcc-11.2.0/gcc-final-build
( cd $BUILD_DIR/gcc-11.2.0/gcc-final-build && \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    MAKEINFO=missing \
    $BUILD_DIR/gcc-11.2.0/configure \
    --build=$CONFIG_HOST \
    --disable-decimal-float \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libsanitizer \
    --disable-libssp \
    --disable-multilib \
    --enable-__cxa_atexit \
    --enable-languages=c,c++ \
    --enable-shared \
    --enable-threads \
    --enable-tls \
    --host=$CONFIG_HOST \
    --prefix=$TOOLS_DIR \
    --target=$CONFIG_TARGET \
    --with-abi="$CONFIG_GCC_ABI" \
    --with-bugurl="$CONFIG_BUG_URL" \
    --with-build-time-tools=$TOOLS_DIR/$CONFIG_TARGET/bin \
    --with-cpu="$CONFIG_GCC_CPU" \
    --with-gnu-ld \
    --with-pkgversion="$CONFIG_PKG_VERSION" \
    --with-sysroot=$SYSROOT_DIR )
make -j$PARALLEL_JOBS AS_FOR_TARGET="$TOOLS_DIR/bin/$CONFIG_TARGET-as" LD_FOR_TARGET="$TOOLS_DIR/bin/$CONFIG_TARGET-ld" gcc_cv_libc_provides_ssp=yes -C $BUILD_DIR/gcc-11.2.0/gcc-final-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gcc-11.2.0/gcc-final-build
for libstdc in libstdc++ ; do
    cp -dpvf $TOOLS_DIR/$CONFIG_TARGET/lib*/$libstdc.a $SYSROOT_DIR/usr/lib/ ;
done
for libstdc in libstdc++ ; do
    cp -dpvf $TOOLS_DIR/$CONFIG_TARGET/lib*/$libstdc.so* $SYSROOT_DIR/usr/lib/ ;
done
if [ ! -e $TOOLS_DIR/bin/$CONFIG_TARGET-cc ]; then
    ln -vf $TOOLS_DIR/bin/$CONFIG_TARGET-gcc $TOOLS_DIR/bin/$CONFIG_TARGET-cc
fi
rm -rf $BUILD_DIR/gcc-11.2.0

step "[17/32] libuv 1.42.0"
extract $SOURCES_DIR/libuv-v1.42.0.tar.gz $BUILD_DIR
( cd $BUILD_DIR/libuv-v1.42.0 && sh autogen.sh )
( cd $BUILD_DIR/libuv-v1.42.0 && \
    ./configure \
    --prefix=$TOOLS_DIR \
	--disable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libuv-v1.42.0
make -j$PARALLEL_JOBS install -C $BUILD_DIR/libuv-v1.42.0
rm -rf $BUILD_DIR/libuv-v1.42.0

step "[18/32] OpenSSL 1.1.1d"
extract $SOURCES_DIR/openssl-1.1.1d.tar.gz $BUILD_DIR
( cd $BUILD_DIR/openssl-1.1.1d && \
    ./Configure \
    linux-x86_64 \
    --prefix=$TOOLS_DIR \
    --openssldir=$TOOLS_DIR/etc/ssl \
    shared \
    zlib-dynamic )
sed -i -e "s# build_tests##" $BUILD_DIR/openssl-1.1.1d/Makefile
make -j1 -C $BUILD_DIR/openssl-1.1.1d
make -j1 install -C $BUILD_DIR/openssl-1.1.1d
rm -rf $BUILD_DIR/openssl-1.1.1d

step "[19/32] Curl 7.79.0"
extract $SOURCES_DIR/curl-7.79.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/curl-7.79.0 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --with-openssl \
    --enable-threaded-resolver \
    --with-ca-path=$TOOLS_DIR/etc/ssl/certs )
make -j$PARALLEL_JOBS -C $BUILD_DIR/curl-7.79.0
make -j$PARALLEL_JOBS install -C $BUILD_DIR/curl-7.79.0
rm -rf $BUILD_DIR/curl-7.79.0

step "[20/32] nghttp2 1.44.0"
extract $SOURCES_DIR/nghttp2-1.44.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/nghttp2-1.44.0 && \
    ./configure \
    --prefix=$TOOLS_DIR \
	--disable-static \
	--enable-lib-only )
make -j$PARALLEL_JOBS -C $BUILD_DIR/nghttp2-1.44.0
make -j$PARALLEL_JOBS install -C $BUILD_DIR/nghttp2-1.44.0
rm -rf $BUILD_DIR/nghttp2-1.44.0

step "[21/32] Expat 2.4.1"
extract $SOURCES_DIR/expat-2.4.1.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/expat-2.4.1 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/expat-2.4.1
make -j$PARALLEL_JOBS install -C $BUILD_DIR/expat-2.4.1
rm -rf $BUILD_DIR/expat-2.4.1

step "[22/32] libarchive 3.5.2"
extract $SOURCES_DIR/libarchive-3.5.2.tar.xz $BUILD_DIR
( cd $BUILD_DIR/libarchive-3.5.2 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libarchive-3.5.2
make -j$PARALLEL_JOBS install -C $BUILD_DIR/libarchive-3.5.2
rm -rf $BUILD_DIR/libarchive-3.5.2

step "[23/32] Cmake 3.21.3"
extract $SOURCES_DIR/cmake-3.21.3.tar.gz $BUILD_DIR
sed -i '/"lib64"/s/64//' $BUILD_DIR/cmake-3.21.3/Modules/GNUInstallDirs.cmake
mkdir $BUILD_DIR/cmake-3.21.3/cmake-build
( cd $BUILD_DIR/cmake-3.21.3/cmake-build && 
    CFLAGS="-O2" CPPFLAGS="-O2" CXXFLAGS="-O2" \
    $BUILD_DIR/cmake-3.21.3/bootstrap \
    --prefix=$TOOLS_DIR \
    --system-libs \
    --no-system-jsoncpp \
    --no-system-librhash \
    --no-qt-gui \
    --parallel=$PARALLEL_JOBS )
make -j$PARALLEL_JOBS -C $BUILD_DIR/cmake-3.21.3/cmake-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/cmake-3.21.3/cmake-build
rm -rf $BUILD_DIR/cmake-3.21.3

step "[24/32] libffi 3.2.1"
extract $SOURCES_DIR/libffi-3.2.1.tar.gz $BUILD_DIR
sed -e '/^includesdir/ s/$(libdir).*$/$(includedir)/' \
    -i $BUILD_DIR/libffi-3.2.1/include/Makefile.in
sed -e '/^includedir/ s/=.*$/=@includedir@/' \
    -e 's/^Cflags: -I${includedir}/Cflags:/' \
    -i $BUILD_DIR/libffi-3.2.1/libffi.pc.in
( cd $BUILD_DIR/libffi-3.2.1 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libffi-3.2.1
make -j$PARALLEL_JOBS install -C $BUILD_DIR/libffi-3.2.1
rm -rf $BUILD_DIR/libffi-3.2.1

step "[25/32] bzip2 1.0.8"
extract $SOURCES_DIR/bzip2-1.0.8.tar.gz $BUILD_DIR
make -j$PARALLEL_JOBS -f Makefile-libbz2_so -C $BUILD_DIR/bzip2-1.0.8
make -j$PARALLEL_JOBS -C $BUILD_DIR/bzip2-1.0.8
make -j$PARALLEL_JOBS PREFIX=$TOOLS_DIR install -C $BUILD_DIR/bzip2-1.0.8
cp -v $BUILD_DIR/bzip2-1.0.8/bzip2-shared $TOOLS_DIR/bin/bzip2
cp -av $BUILD_DIR/bzip2-1.0.8/libbz2.so* $TOOLS_DIR/lib
ln -sv $BUILD_DIR/bzip2-1.0.8/libbz2.so.1.0 $TOOLS_DIR/lib/libbz2.so
rm -rf $BUILD_DIR/bzip2-1.0.8

step "[26/32] xz 5.2.5"
extract $SOURCES_DIR/xz-5.2.5.tar.xz $BUILD_DIR
( cd $BUILD_DIR/xz-5.2.5 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static )
make -j$PARALLEL_JOBS -C $BUILD_DIR/xz-5.2.5
make -j$PARALLEL_JOBS install -C $BUILD_DIR/xz-5.2.5
rm -rf $BUILD_DIR/xz-5.2.5

step "[27/32] Python 3.9.7"
extract $SOURCES_DIR/Python-3.9.7.tar.xz $BUILD_DIR
( cd $BUILD_DIR/Python-3.9.7 && \
    CXX="g++" \
    ./configure \
    --prefix=$TOOLS_DIR \
    --enable-shared \
    --with-system-expat \
    --with-system-ffi \
    --with-ensurepip=yes \
    --enable-optimizations )
make -j$PARALLEL_JOBS -C $BUILD_DIR/Python-3.9.7
make -j$PARALLEL_JOBS install -C $BUILD_DIR/Python-3.9.7
rm -rf $BUILD_DIR/Python-3.9.7

step "[28/32] Icu 69.1"
extract $SOURCES_DIR/icu4c-69_1-src.tgz $BUILD_DIR
( cd $BUILD_DIR/icu/source && \
    ac_cv_func_strtod_l=no \
    LIBS="-latomic" \
    ./configure \
    --prefix=$TOOLS_DIR \
	--disable-samples \
    --disable-samples \
	--disable-tests \
	--disable-extras \
	--disable-icuio \
	--disable-layout \
	--disable-renaming )
make -j$PARALLEL_JOBS -C $BUILD_DIR/icu/source
make -j$PARALLEL_JOBS install -C $BUILD_DIR/icu/source
rm -rf $BUILD_DIR/icu

step "[29/32] c-ares 1.17.2"
extract $SOURCES_DIR/c-ares-1.17.2.tar.gz $BUILD_DIR
mkdir $BUILD_DIR/c-ares-1.17.2/build
( cd $BUILD_DIR/c-ares-1.17.2/build && cmake -DCMAKE_INSTALL_PREFIX=$TOOLS_DIR .. )
make -j$PARALLEL_JOBS -C $BUILD_DIR/c-ares-1.17.2/build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/c-ares-1.17.2/build
rm -rf $BUILD_DIR/c-ares-1.17.2

step "[30/32] Node.js 14.17.6"
extract $SOURCES_DIR/node-v14.17.6.tar.xz $BUILD_DIR
sed -i 's|ares_nameser.h|arpa/nameser.h|' $BUILD_DIR/node-v14.17.6/src/cares_wrap.h
( cd $BUILD_DIR/node-v14.17.6 && \
    PYTHON=$TOOLS_DIR/bin/python3 \
    $TOOLS_DIR/bin/python3 ./configure \
    --prefix=$TOOLS_DIR \
    --without-snapshot \
    --without-dtrace \
    --without-etw \
    --shared-openssl \
    --shared-openssl-includes=$TOOLS_DIR/include/openssl \
    --shared-openssl-libpath=$TOOLS_DIR/lib \
    --shared-zlib \
    --no-cross-compiling \
    --with-intl=none )
make -j$PARALLEL_JOBS CXXFLAGS="-O2 -I$TOOLS_DIR/include -DU_DISABLE_RENAMING=1" LDFLAGS.host="-L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib" NO_LOAD=cctest.target.mk -C $BUILD_DIR/node-v14.17.6
make -j$PARALLEL_JOBS install -C $BUILD_DIR/node-v14.17.6
rm -rf $BUILD_DIR/node-v14.17.6

step "[31/32] mkpasswd 5.0.26"
gcc -O2 -I$TOOLS_DIR/usr/include -L$TOOLS_DIR/lib -L$TOOLS_DIR/usr/lib -Wl,-rpath,$TOOLS_DIR/usr/lib $SUPPORT_DIR/mkpasswd/mkpasswd.c $SUPPORT_DIR/mkpasswd/utils.c -o $TOOLS_DIR/usr/bin/mkpasswd -lcrypt
chmod 755 $TOOLS_DIR/usr/bin/mkpasswd

step "[32/32] makedevs"
gcc -O2 -I$TOOLS_DIR/include $SUPPORT_DIR/makedevs/makedevs.c -o $TOOLS_DIR/bin/makedevs -L$TOOLS_DIR/lib -L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib
chmod 755 $TOOLS_DIR/bin/makedevs

do_strip

success "\nTotal toolchain build time: $(timer $total_build_time)\n"