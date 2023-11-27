#!/bin/bash
#
# PiCLFS toolchain build script
# Optional parameteres below:
set +h
set -o nounset
set -o errexit
umask 022

export LC_ALL=POSIX
export PARALLEL_JOBS=`cat /proc/cpuinfo | grep cores | wc -l`
export CONFIG_LINUX_ARCH="arm64"
export CONFIG_TARGET="aarch64-linux-gnu"
export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

export WORKSPACE_DIR=$PWD
export SOURCES_DIR=$WORKSPACE_DIR/sources
export OUTPUT_DIR=$WORKSPACE_DIR/out
export BUILD_DIR=$OUTPUT_DIR/build
export TOOLS_DIR=$OUTPUT_DIR/tools
export SYSROOT_DIR=$TOOLS_DIR/$CONFIG_TARGET/sysroot

export CFLAGS="-O2 -I$TOOLS_DIR/include"
export CPPFLAGS="-O2 -I$TOOLS_DIR/include"
export CXXFLAGS="-O2 -I$TOOLS_DIR/include"
export LDFLAGS="-L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib"
export PATH="$TOOLS_DIR/bin:$TOOLS_DIR/sbin:$PATH"

export PKG_CONFIG="$TOOLS_DIR/bin/pkg-config"
export PKG_CONFIG_SYSROOT_DIR="/"
export PKG_CONFIG_LIBDIR="$TOOLS_DIR/lib/pkgconfig:$TOOLS_DIR/share/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1

CONFIG_STRIP_AND_DELETE_DOCS=1

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
    name=$(echo $1 | rev | cut -d "/" -f 1 | rev | cut -d "." -f 1)
    mkdir $2/$name
    tar -nxf $1 -C $2/$name --strip-component 1
    case $1 in
        *.tgz) tar -zxf $1 -C $2/$name --strip-component 1 ;;
        *.tar.gz) tar -zxf $1 -C $2/$name --strip-component 1 ;;
        *.tar.bz2) tar -jxf $1 -C $2/$name --strip-component 1 ;;
        *.tar.xz) tar -Jxf $1 -C $2/$name --strip-component 1 ;;
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
      autoconf.tar.xz
      automake.tar.xz
      binutils.tar.xz
      bison.tar.gz
      confuse.tar.xz
      dosfstools.tar.gz
      e2fsprogs.tar.gz
      elfutils.tar.bz2
      fakeroot.tar.gz
      flex.tar.gz
      gawk.tar.xz
      gcc.tar.xz
      genimage.tar.xz
      glibc.tar.xz
      gmp.tar.xz
      libtool.tar.xz
      m4.tar.xz
      mpc.tar.gz
      mpfr.tar.xz
      mtools.tar.bz2
      openssl.tar.gz
      pkgconf.tar.xz
      kernel.tar.gz
      util-linux.tar.xz
      zlib.tar.gz"

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

step "[1/25] Create toolchain directory."
rm -rf $BUILD_DIR $TOOLS_DIR
mkdir -pv $BUILD_DIR $TOOLS_DIR
ln -svf . $TOOLS_DIR/usr

step "[2/25] Create the sysroot directory"
mkdir -pv $SYSROOT_DIR
ln -svf . $SYSROOT_DIR/usr
mkdir -pv $SYSROOT_DIR/lib
if [[ "$CONFIG_LINUX_ARCH" = "arm" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib32
fi
if [[ "$CONFIG_LINUX_ARCH" = "arm64" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib64
fi

step "[3/25] Pkgconf"
extract $SOURCES_DIR/pkgconf.tar.xz $BUILD_DIR
( cd $BUILD_DIR/pkgconf && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-dependency-tracking )
make -j$PARALLEL_JOBS -C $BUILD_DIR/pkgconf
make -j$PARALLEL_JOBS install -C $BUILD_DIR/pkgconf
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
rm -rf $BUILD_DIR/pkgconf

step "[4/25] M4"
extract $SOURCES_DIR/m4.tar.xz $BUILD_DIR
( cd $BUILD_DIR/m4 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/m4
make -j$PARALLEL_JOBS install -C $BUILD_DIR/m4
rm -rf $BUILD_DIR/m4

step "[5/25] Libtool"
extract $SOURCES_DIR/libtool.tar.xz $BUILD_DIR
( cd $BUILD_DIR/libtool && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libtool
make -j$PARALLEL_JOBS install -C $BUILD_DIR/libtool
rm -rf $BUILD_DIR/libtool

step "[6/25] Autoconf"
extract $SOURCES_DIR/autoconf.tar.xz $BUILD_DIR
( cd $BUILD_DIR/autoconf && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/autoconf
make -j$PARALLEL_JOBS install -C $BUILD_DIR/autoconf
rm -rf $BUILD_DIR/autoconf

step "[7/25] Automake"
extract $SOURCES_DIR/automake.tar.xz $BUILD_DIR
( cd $BUILD_DIR/automake && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/automake
make -j$PARALLEL_JOBS install -C $BUILD_DIR/automake
mkdir -p $SYSROOT_DIR/usr/share/aclocal
rm -rf $BUILD_DIR/automake

step "[8/25] Zlib"
extract $SOURCES_DIR/zlib.tar.gz $BUILD_DIR
( cd $BUILD_DIR/zlib && ./configure --prefix=$TOOLS_DIR )
make -j1 -C $BUILD_DIR/zlib
make -j1 install -C $BUILD_DIR/zlib
rm -rf $BUILD_DIR/zlib

step "[9/25] Util-linux"
extract $SOURCES_DIR/util-linux.tar.xz $BUILD_DIR
( cd $BUILD_DIR/util-linux && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --without-python \
    --enable-libblkid \
    --enable-libmount \
    --enable-libuuid \
    --without-ncurses \
    --without-ncursesw \
    --without-tinfo \
    --disable-makeinstall-chown \
    --disable-agetty \
    --disable-chfn-chsh \
    --disable-chmem \
    --disable-login \
    --disable-lslogins \
    --disable-mesg \
    --disable-more \
    --disable-newgrp \
    --disable-nologin \
    --disable-nsenter \
    --disable-pg \
    --disable-rfkill \
    --disable-schedutils \
    --disable-setpriv \
    --disable-setterm \
    --disable-su \
    --disable-sulogin \
    --disable-tunelp \
    --disable-ul \
    --disable-unshare \
    --disable-uuidd \
    --disable-vipw \
    --disable-wall \
    --disable-wdctl \
    --disable-write \
    --disable-zramctl )
make -j$PARALLEL_JOBS -C $BUILD_DIR/util-linux
make -j$PARALLEL_JOBS install -C $BUILD_DIR/util-linux
rm -rf $BUILD_DIR/util-linux

step "[10/25] E2fsprogs"
extract $SOURCES_DIR/e2fsprogs.tar.gz $BUILD_DIR
( cd $BUILD_DIR/e2fsprogs && \
    ac_cv_path_LDCONFIG=true \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-defrag \
    --disable-e2initrd-helper \
    --disable-fuse2fs \
    --disable-libblkid \
    --disable-libuuid \
    --disable-testio-debug \
    --enable-symlink-install \
    --enable-elf-shlibs \
    --with-crond-dir=no )
make -j$PARALLEL_JOBS -C $BUILD_DIR/e2fsprogs
make -j$PARALLEL_JOBS install -C $BUILD_DIR/e2fsprogs
rm -rf $BUILD_DIR/e2fsprogs

step "[11/25] Fakeroot"
extract $SOURCES_DIR/fakeroot.tar.gz $BUILD_DIR
( cd $BUILD_DIR/fakeroot && \
    ac_cv_header_sys_capability_h=no \
    ac_cv_func_capset=no \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/fakeroot
make -j$PARALLEL_JOBS install -C $BUILD_DIR/fakeroot
rm -rf $BUILD_DIR/fakeroot

step "[12/25] Bison"
extract $SOURCES_DIR/bison.tar.gz $BUILD_DIR
( cd $BUILD_DIR/bison && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bison
make -j$PARALLEL_JOBS install -C $BUILD_DIR/bison
rm -rf $BUILD_DIR/bison

step "[13/25] Gawk"
extract $SOURCES_DIR/gawk.tar.xz $BUILD_DIR
( cd $BUILD_DIR/gawk && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --without-readline \
    --without-mpfr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gawk
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gawk
rm -rf $BUILD_DIR/gawk

step "[14/25] Binutils"
extract $SOURCES_DIR/binutils.tar.xz $BUILD_DIR
mkdir -pv $BUILD_DIR/binutils/binutils-build
( cd $BUILD_DIR/binutils/binutils-build && \
    MAKEINFO=true \
    $BUILD_DIR/binutils/configure \
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
make -j$PARALLEL_JOBS configure-host -C $BUILD_DIR/binutils/binutils-build
make -j$PARALLEL_JOBS -C $BUILD_DIR/binutils/binutils-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/binutils/binutils-build
rm -rf $BUILD_DIR/binutils

step "[15/25] Gcc - Static"
extract $SOURCES_DIR/gcc.tar.xz $BUILD_DIR
extract $SOURCES_DIR/gmp.tar.xz $BUILD_DIR/gcc
extract $SOURCES_DIR/mpfr.tar.xz $BUILD_DIR/gcc
extract $SOURCES_DIR/mpc.tar.gz $BUILD_DIR/gcc
mkdir -pv $BUILD_DIR/gcc/gcc-build

( cd $BUILD_DIR/gcc/gcc-build && \
    MAKEINFO=missing \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    $BUILD_DIR/gcc/configure \
    --prefix=$TOOLS_DIR \
    --build=$CONFIG_HOST \
    --host=$CONFIG_HOST \
    --target=$CONFIG_TARGET \
    --with-sysroot=$SYSROOT_DIR \
    --disable-static \
    --enable-__cxa_atexit \
    --with-gnu-ld \
    --disable-libssp \
    --disable-multilib \
    --disable-decimal-float \
    --disable-libquadmath \
    --enable-tls \
    --enable-threads \
    --without-isl \
    --without-cloog \
    --with-abi="lp64" \
    --with-cpu=cortex-a53 \
    --enable-languages=c \
    --disable-shared \
    --without-headers \
    --disable-threads \
    --with-newlib \
    --disable-largefile )
make -j$PARALLEL_JOBS gcc_cv_libc_provides_ssp=yes all-gcc all-target-libgcc -C $BUILD_DIR/gcc/gcc-build
make -j$PARALLEL_JOBS install-gcc install-target-libgcc -C $BUILD_DIR/gcc/gcc-build
rm -rf $BUILD_DIR/gcc

step "[16/25] Raspberry Pi Linux API Headers"
extract $SOURCES_DIR/kernel.tar.gz $BUILD_DIR
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH mrproper -C $BUILD_DIR/kernel
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH headers_check -C $BUILD_DIR/kernel
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH INSTALL_HDR_PATH=$SYSROOT_DIR headers_install -C $BUILD_DIR/kernel
rm -rf $BUILD_DIR/kernel

step "[17/25] glibc"
extract $SOURCES_DIR/glibc.tar.xz $BUILD_DIR
mkdir $BUILD_DIR/glibc/glibc-build
( cd $BUILD_DIR/glibc/glibc-build && \
    CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc" \
    CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++" \
    AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar" \
    AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as" \
    LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld" \
    RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib" \
    READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf" \
    STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip" \
    CFLAGS="-O2 " CPPFLAGS="" CXXFLAGS="-O2 " LDFLAGS="" \
    ac_cv_path_BASH_SHELL=/bin/sh \
    libc_cv_forced_unwind=yes \
    libc_cv_ssp=no \
    $BUILD_DIR/glibc/configure \
    --target=$CONFIG_TARGET \
    --host=$CONFIG_TARGET \
    --build=$CONFIG_HOST \
    --prefix=/usr \
    --enable-shared \
    --without-cvs \
    --disable-profile \
    --without-gd \
    --enable-obsolete-rpc \
    --enable-kernel=4.19 \
    --with-headers=$SYSROOT_DIR/usr/include )
make -j$PARALLEL_JOBS -C $BUILD_DIR/glibc/glibc-build
make -j$PARALLEL_JOBS install_root=$SYSROOT_DIR install -C $BUILD_DIR/glibc/glibc-build
rm -rf $BUILD_DIR/glibc

step "[18/25] Gcc - Final"
tar -Jxf $SOURCES_DIR/gcc.tar.xz -C $BUILD_DIR
extract $SOURCES_DIR/gmp.tar.xz $BUILD_DIR/gcc
mv -v $BUILD_DIR/gcc/gmp $BUILD_DIR/gcc/gmp
extract $SOURCES_DIR/mpfr.tar.xz $BUILD_DIR/gcc
mv -v $BUILD_DIR/gcc/mpfr $BUILD_DIR/gcc/mpfr
extract $SOURCES_DIR/mpc.tar.gz $BUILD_DIR/gcc
mv -v $BUILD_DIR/gcc/mpc $BUILD_DIR/gcc/mpc
mkdir -v $BUILD_DIR/gcc/gcc-build
( cd $BUILD_DIR/gcc/gcc-build && \
    MAKEINFO=missing \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    $BUILD_DIR/gcc/configure \
    --prefix=$TOOLS_DIR \
    --build=$CONFIG_HOST \
    --host=$CONFIG_HOST \
    --target=$CONFIG_TARGET \
    --with-sysroot=$SYSROOT_DIR \
    --enable-__cxa_atexit \
    --with-gnu-ld \
    --disable-libssp \
    --disable-multilib \
    --disable-decimal-float \
    --disable-libquadmath \
    --enable-tls \
    --enable-threads \
    --with-abi="lp64" \
    --with-cpu=cortex-a53 \
    --enable-languages=c,c++ \
    --with-build-time-tools=$TOOLS_DIR/$CONFIG_TARGET/bin \
    --enable-shared \
    --disable-libgomp )
make -j$PARALLEL_JOBS gcc_cv_libc_provides_ssp=yes -C $BUILD_DIR/gcc/gcc-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gcc/gcc-build
if [ ! -e $TOOLS_DIR/bin/$CONFIG_TARGET-cc ]; then
    ln -vf $TOOLS_DIR/bin/$CONFIG_TARGET-gcc $TOOLS_DIR/bin/$CONFIG_TARGET-cc
fi
rm -rf $BUILD_DIR/gcc

step "[19/25] Elfutils"
extract $SOURCES_DIR/elfutils.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/elfutils && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-debuginfod )
make -j$PARALLEL_JOBS -C $BUILD_DIR/elfutils
make -j$PARALLEL_JOBS install -C $BUILD_DIR/elfutils
rm -rf $BUILD_DIR/elfutils

step "[20/25] Dosfstools"
extract $SOURCES_DIR/dosfstools.tar.xz $BUILD_DIR
( cd $BUILD_DIR/dosfstools && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --enable-compat-symlinks )
make -j$PARALLEL_JOBS -C $BUILD_DIR/dosfstools
make -j$PARALLEL_JOBS install -C $BUILD_DIR/dosfstools
rm -rf $BUILD_DIR/dosfstools

step "[21/25] libconfuse"
extract $SOURCES_DIR/confuse.tar.xz $BUILD_DIR
( cd $BUILD_DIR/confuse && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/confuse
make -j$PARALLEL_JOBS install -C $BUILD_DIR/confuse
rm -rf $BUILD_DIR/confuse

step "[22/25] Genimage"
extract $SOURCES_DIR/genimage.tar.xz $BUILD_DIR
( cd $BUILD_DIR/genimage && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/genimage
make -j$PARALLEL_JOBS install -C $BUILD_DIR/genimage
rm -rf $BUILD_DIR/genimage

step "[23/25] Flex"
extract $SOURCES_DIR/flex.tar.gz $BUILD_DIR
( cd $BUILD_DIR/flex && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-doc )
make -j$PARALLEL_JOBS -C $BUILD_DIR/flex
make -j$PARALLEL_JOBS install -C $BUILD_DIR/flex
rm -rf $BUILD_DIR/flex

step "[24/25] Mtools"
extract $SOURCES_DIR/mtools.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/mtools && \
    ac_cv_lib_bsd_gethostbyname=no \
    ac_cv_lib_bsd_main=no \
    ac_cv_path_INSTALL_INFO= \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-doc )
make -j1 -C $BUILD_DIR/mtools
make -j1 install -C $BUILD_DIR/mtools
rm -rf $BUILD_DIR/mtools

step "[25/25] Openssl "
extract $SOURCES_DIR/openssl.tar.gz $BUILD_DIR
( cd $BUILD_DIR/openssl && \
    ./config \
    --prefix=$TOOLS_DIR \
    --openssldir=$TOOLS_DIR/etc/ssl \
    --libdir=lib \
    no-tests \
    no-fuzz-libfuzzer \
    no-fuzz-afl \
    shared \
    zlib-dynamic )
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssl
make -j$PARALLEL_JOBS install -C $BUILD_DIR/openssl
rm -rf $BUILD_DIR/openssl

do_strip

success "\nTotal toolchain build time: $(timer $total_build_time)\n"
