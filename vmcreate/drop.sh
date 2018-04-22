#!/bin/bash
PUPPETBIN=/opt/puppetlabs/bin/puppetserver
if [ $# -ne 1 ];then
    echo "Usage: `basename $0` {vmname}"
    exit 1
fi

VM=$1
DOMAIN=labolinux.fr
VGNAME=vg1

test -f $VM.sh || { echo "Profile $VM.sh not found. Aborting."; exit 1 ; }

. ./$VM.sh

# Destroy any previous machine for recycling
sudo virsh destroy $VM
sudo virsh undefine $VM

# Destroy the VM disks
if [ -n "$disk1" ];then
sudo lvremove -f /dev/${VGNAME}/vm${VM}
fi

if [ -n "$disk2" ];then
sudo lvremove -f /dev/${VGNAME}/vm${VM}_disk2
fi

if [ -n "$disk3" ];then
sudo lvremove -f /dev/${VGNAME}/vm${VM}_disk3
fi

# Clean any previous puppet key for the machine
test -f $PUPPETBIN
if [ $? -eq 0 ];then
    sudo $PUPPETBIN ca clean --certname $VM.$DOMAIN
fi

# Delete any previous known ssh key for the host
IP=$(getent ahostsv4 $VM | awk 'END{ print $1 }')

ssh-keygen -f "$HOME/.ssh/known_hosts" -R $VM
ssh-keygen -f "$HOME/.ssh/known_hosts" -R $VM.labolinux.fr
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
