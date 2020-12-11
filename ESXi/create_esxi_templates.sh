#!/bin/bash

#creates a ESXi kickstart based template
#This script requires a working metalcloud-cli and jq tools.

#Note this will delete the existing template instead of updating it.

if [ "$#" -ne 2 ]; then
    echo "syntax: $0 <template-id> <os-version (eg: 8.)>"
    exit
fi

TEMPLATE_VERSION="$2" 
TEMPLATE_DISPLAY_NAME="ESXi $TEMPLATE_VERSION"
TEMPLATE_DESCRIPTION="$TEMPLATE_DISPLAY_NAME"
TEMPLATE_LABEL=$1
TEMPLATE_ROOT=".tftp/boot/images/ESXi-$TEMPLATE_VERSION"


SOURCES="./$TEMPLATE_VERSION"

MC="metalcloud-cli"

DATACENTER_NAME="$METALCLOUD_DATACENTER"
REPO_URL=`metalcloud-cli datacenter get --id $DATACENTER_NAME --show-config -format json | jq ".[0].CONFIG | fromjson |.repoURLRoot" -r`
TEMPLATE_BASE=$REPO_URL/$TEMPLATE_ROOT
TEMPLATE_IPXE_BASE="$REPO_URL/.tftp/boot/ipxe"

if $MC os-template get --id "$TEMPLATE_LABEL" 2>&1 >/dev/null; then
    if $MC os-template delete --id "$TEMPLATE_LABEL" --autoconfirm 2>&1 >/dev/null; then
        OS_TEMPLATE_COMMAND=create
        OS_TEMPLATE_FLAG=label
    else
        OS_TEMPLATE_COMMAND=update
        OS_TEMPLATE_FLAG=id
    fi
else
    OS_TEMPLATE_COMMAND=create
    OS_TEMPLATE_FLAG=label
fi

#create the template
$MC os-template $OS_TEMPLATE_COMMAND \
--$OS_TEMPLATE_FLAG "$TEMPLATE_LABEL" \
--display-name "$TEMPLATE_DISPLAY_NAME" \
--description "$TEMPLATE_DESCRIPTION" \
--boot-type "uefi_only" \
--os-architecture "x86_64" \
--os-type "ESXi" \
--os-version "$TEMPLATE_VERSION" \
--use-autogenerated-initial-password \
--initial-user "root" \
--initial-ssh-port 22 \
--boot-methods-supported "local_drives"

#first param is asset name, 
#second param is asset url relative to $TEMPLATE_IPXE_BASE 
#third param is usage
function addIPXEBinaryURLAsset {
    $MC asset create --url "$TEMPLATE_IPXE_BASE/$2" --filename "$1-$TEMPLATE_LABEL" \
    --template-id $TEMPLATE_LABEL --mime "application/octet-stream" --path "/$1" \
    --delete-if-exists --usage "$3" --return-id
}

#first param is asset name, 
#second param is asset url relative to $TEMPLATE_BASE 
#third param is usage
function addBinaryURLAsset {
    $MC asset create --url "$TEMPLATE_BASE/$2" --filename "$1-$TEMPLATE_LABEL" \
    --template-id $TEMPLATE_LABEL --mime "application/octet-stream" --path "/$1" \
    --delete-if-exists --usage "$3"
}

#firt param is file name on disk
#second param is path in tftp/http
#third param is params accepted
function addFileAsset {
    cat $SOURCES/$1 | $MC asset create --filename "$1-$TEMPLATE_LABEL" --template-id $TEMPLATE_LABEL \
    --mime "text/plain" --path "$2" --delete-if-exists --pipe
}

#add ipxe.efi to boot the ESXi installer from an HTTP server
TEMPLATE_INSTALL_BOOTLOADER_ASSET=`addIPXEBinaryURLAsset "ipxe.efi" "ipxe.efi" "bootloader"`

#set the ipxe.efi bootloader as the template's default bootloader
metalcloud-cli os-template update --id "$TEMPLATE_LABEL" --install-bootloader-asset "$TEMPLATE_INSTALL_BOOTLOADER_ASSET"

#add bootx64 bootloader uefi
addBinaryURLAsset "bootx64.efi" "efi/boot/bootx64.efi"

#add ipxe config file
addFileAsset "esxi.ipxe" "/ipxe_config_install"

#add esxi-http.cfg config file
addFileAsset "esxi-http.cfg" "/boot.cfg"

#add kickstart file ks.cfg
addFileAsset "ks.cfg" "/ESXi/ks.cfg-esxi-700-v2"

