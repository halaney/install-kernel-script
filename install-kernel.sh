#!/usr/bin/bash

set -e

print_help()
{
    cat << __EOF__
This script is useful for incrementally uploading locally built
kernels to standards adhering systems. It will copy the modules,
the <kernel_target_path> (arch/arm64/boot/Image.gz, arch/.../vmlinuz.efi, etc),
and the dtbs to the target via rsync. It will also install them
(i.e. generate an initramfs and BLS entry) with kernel-install.

This script assumes you've built already and just need to
upload the artifacts.

    usage: $0 [options] <kernel_target_path> <target_ip>

    Options:
	-s skip kernel-install (which can be slow on some systems)
	-a ARCH= value to pass to the commands (arm64, etc)
	-c CC= value to pass to the commands (clang, etc)
__EOF__
}


while getopts ":s:a:c:" option; do
	case "${option}" in
		s)
			SKIP_KERNEL_INSTALL=true
			;;
		a)
			ARCH="${OPTARG}"
			;;
		c)
			CC="${OPTARG}"
			;;
		*)
			echo "error: invalid option ${OPTARG}"
                        echo ""
			print_help
			exit
			;;
	esac
done
shift "$((OPTIND - 1))"

if [[ "${ARCH}" = "" ]] ; then
	ARCH="$(uname -m)"
fi

KERNEL_TARGET=$1
if [[ "${KERNEL_TARGET}" = "" ]] ; then
    echo "Missing kernel_target_path parameter path"
	echo ""
	print_help
	exit 1
fi

TARGET_IP=$2
if [[ "${TARGET_IP}" = "" ]] ; then
	echo "Missing target_ip parameter"
	echo ""
	print_help
	exit 1
fi

# Grab the kernelrelease string
KERNELRELEASE="$(make CC="${CC}" ARCH="${ARCH}" - -s kernelrelease)"

# locally install the modules and dtbs
LOCALMODDIR="$(mktemp -d)"
LOCALDTBSDIR="$(mktemp -d)"
make -s INSTALL_MOD_PATH="${LOCALMODDIR}" CC="${CC}" ARCH="${ARCH}" modules_install
make -s INSTALL_DTBS_PATH="${LOCALDTBSDIR}" CC="${CC}" ARCH="${ARCH}" dtbs_install

# copy the modules, ${KERNEL_TARGET}, and dtbs
rsync -az --partial --no-owner --no-group "${LOCALMODDIR}"/lib/modules/"${KERNELRELEASE}"/ root@"${TARGET_IP}":/lib/modules/"${KERNELRELEASE}"
rsync -az --partial --no-owner --no-group "${KERNEL_TARGET}" root@"${TARGET_IP}":/boot/vmlinuz-"${KERNELRELEASE}"
rsync -az --partial --no-owner --no-group "${LOCALDTBSDIR}"/ root@"${TARGET_IP}":/boot/dtb-"${KERNELRELEASE}"/

# kernel-install to get a BLS entry and initramfs
if [[ "${SKIP_KERNEL_INSTALL}" != true ]] ; then
	ssh root@"${TARGET_IP}" "kernel-install add ${KERNELRELEASE} /boot/vmlinuz-${KERNELRELEASE}"
fi

# TODO: cleanup regardless of failures above (set -e prevents this)
# Clean up
rm -rf "${LOCALMODDIR}"
rm -rf "${LOCALDTBSDIR}"
