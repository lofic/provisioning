#!/bin/bash
PUPPETBIN=/opt/puppetlabs/bin/puppetserver
if [ $# -ne 1 ];then
    echo "Usage: `basename $0` {vmname}"
    exit 1
fi

VM=$1
DOMAIN=labolinux.fr
VGNAME=vg1
BRNAME=br0

test -f $VM.sh || { echo "Profile $VM.sh not found. Aborting."; exit 1 ; }

. ./$VM.sh

# Destroy any previous machine for recycling
sudo virsh destroy $VM
sudo virsh undefine $VM

# Destroy and recreate the VM disks
if [ -n "$disk1" ];then
sudo lvremove -f /dev/${VGNAME}/vm${VM}
sudo lvcreate -y -W y -Z y -n vm${VM} -L+${disk1} ${VGNAME}
disk1="--disk path=/dev/${VGNAME}/vm${VM},format=raw,bus=virtio"
fi

if [ -n "$disk2" ];then
sudo lvremove -f /dev/${VGNAME}/vm${VM}_disk2
sudo lvcreate -n vm${VM}_disk2 -L+${disk2} ${VGNAME}
disk2="--disk path=/dev/${VGNAME}/vm${VM}_disk2,format=raw,bus=virtio"
fi

if [ -n "$disk3" ];then
sudo lvremove -f /dev/${VGNAME}/vm${VM}_disk3
sudo lvcreate -n vm${VM}_disk3 -L+${disk3} ${VGNAME}
disk3="--disk path=/dev/${VGNAME}/vm${VM}_disk3,format=raw,bus=virtio"
fi

# Clean any previous puppet key for the machine
test -f $PUPPETBIN
if [ $? -eq 0 ];then
    sudo $PUPPETBIN ca clean $VM.$DOMAIN
fi

# Delete any previous known ssh key for the host
IP=$(getent ahostsv4 $VM | awk 'END{ print $1 }')

ssh-keygen -f "$HOME/.ssh/known_hosts" -R $VM
if [ -n "$IP" ]; then
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R $IP
fi

keyline=$(ssh-keygen -l -F $VM | awk '/found: line/ {print $6}')
if [ -n "$keyline" ];then
    sed -i ${keyline}d $HOME/.ssh/known_hosts
fi

if [ -n "$IP" ]; then
    keyline=$(ssh-keygen -l -F $IP | awk '/found: line/ {print $6}')
    if [ -n "$keyline" ];then
        sed -i ${keyline}d $HOME/.ssh/known_hosts
    fi
fi

echo $kspath | grep -q preseed

if [ $? -eq 0 ]; then
    # Debian
    # The preseed file MUST be named preseed.cfg in order for d-i
    # to pick it up from the initrd.
    extraargs='auto console=tty0 console=ttyS0,115200'
else
    # Red Hat
    ksfile=$(basename $kspath)
    extraargs="ks=file:/$ksfile console=tty0 console=ttyS0,115200"

    echo $url | egrep -q 'el7|/7/'

    if [ $? -eq 0 ];then
        # el7
        extraargs+="ksdevice=eth0"
        extraargs+="ip=$ip netmask=255.255.255.00 gateway=192.168.0.10"
        extraargs+="nameserver=192.168.0.10 hostname=$VM.$DOMAIN"
        extraargs+="noipv6"
    else
        # el8
        extraargs+="ksdevice=ens2"
        extraargs+="ip=$ip::192.168.0.10:255.255.255.0:$VM.$DOMAIN:ens2:none"
        extraargs+="ipv6.disable=1"
    fi
fi

# Deploy the new VM
sudo virt-install --connect=qemu:///system \
   --name $VM \
   --ram $memory \
   $disk1 \
   $disk2 \
   $disk3 \
   --network bridge=${BRNAME},model=virtio \
   --vcpus=1 \
   --check-cpu \
   --accelerate \
   --location=$url \
   --initrd-inject=$kspath \
   --extra-args="$extraargs" \
   --nographics
