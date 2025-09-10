#!/bin/bash

set -ex -o pipefail

serial_log="$(pwd)/smoke.serial"

cd binaries

mkdir rootfs
cd rootfs
tar xvf ../xen-image-minimal-qemuarm.tar.bz2
mkdir -p ./root
echo "name=\"test\"
memory=400
vcpus=1
kernel=\"/root/zImage\"
ramdisk=\"/root/initrd.cpio.gz\"
extra=\"console=hvc0 root=/dev/ram0 rdinit=/bin/sh\"
" > root/test.cfg
echo "#!/bin/bash

xl list

xl -vvv create -c /root/test.cfg

" > ./root/xen.start
echo "bash /root/xen.start" >> ./etc/init.d/xen-watchdog

curl --fail --silent --show-error --location --output initrd.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.15/releases/armhf/alpine-minirootfs-3.15.1-armhf.tar.gz
mkdir rootfs
cd rootfs
tar xvzf ../initrd.tar.gz
find . | cpio -R 0:0 -H newc -o | gzip > ../root/initrd.cpio.gz
cd ..
rm -rf rootfs
rm initrd.tar.gz

cp ../zImage ./root
find . | cpio -R 0:0 -H newc -o | gzip > ../initrd.gz
cd ..

# XXX QEMU looks for "efi-virtio.rom" even if it is unneeded
curl -fsSLO https://github.com/qemu/qemu/raw/v5.2.0/pc-bios/efi-virtio.rom
./qemu-system-arm \
   -machine virt \
   -machine virtualization=true \
   -smp 4 \
   -m 2048 \
   -serial stdio \
   -monitor none \
   -display none \
   -machine dumpdtb=virt.dtb

# XXX disable pci to avoid Linux hang
fdtput virt.dtb -p -t s /pcie@10000000 status disabled

# ImageBuilder
echo 'MEMORY_START="0x40000000"
MEMORY_END="0xC0000000"

DEVICE_TREE="virt.dtb"
XEN="xen-qemuarm"
DOM0_KERNEL="zImage"
DOM0_RAMDISK="initrd.gz"
DOM0_CMD="console=hvc0 earlyprintk clk_ignore_unused root=/dev/ram0 rdinit=/sbin/init"
XEN_CMD="console=dtuart dom0_mem=1024M bootscrub=0 console_timestamps=boot"

NUM_DOMUS=0

LOAD_CMD="tftpb"
BOOT_CMD="bootz"
UBOOT_SOURCE="boot.source"
UBOOT_SCRIPT="boot.scr"' > config

rm -rf imagebuilder
git clone --depth 1 https://gitlab.com/xen-project/imagebuilder.git
bash imagebuilder/scripts/uboot-script-gen -t tftp -d . -c config

rm -f ${serial_log}
export TEST_CMD="./qemu-system-arm \
   -machine virt \
   -machine virtualization=true \
   -smp 4 \
   -m 2048 \
   -serial stdio \
   -monitor none \
   -display none \
   -no-reboot \
   -device virtio-net-pci,netdev=n0 \
   -netdev user,id=n0,tftp=./ \
   -bios /usr/lib/u-boot/qemu_arm/u-boot.bin"

export UBOOT_CMD="virtio scan; dhcp; tftpb 0x40000000 boot.scr; source 0x40000000"
export TEST_LOG="${serial_log}"
export BOOT_MSG="Latest ChangeSet: "
export LOG_MSG="Domain-0"
export PASSED="/ #"

../automation/scripts/console.exp | sed 's/\r\+$//'
