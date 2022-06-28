## proof-of-concept for using overlay.d magisk feature
## this feature required patching boot image 
## use this script as customize.sh of your module

# make sure /data/adb/magisk/util_functions.sh is sourced

. /data/adb/magisk/util_functions.sh

MAGISKTMP="$(magisk --path)"
[ -z "$MAGISKTMP" ] && MAGISKTMP=/sbin

magiskboot(){
    /data/adb/magisk/magiskboot "$@"
}


# defined patch ramdisk function, wrapper of this command:
# magiskboot cpio ramdisk.cpio "<command1>" "<command2>" ...

patch_rd(){
    local args=" magiskboot cpio ramdisk.cpio"
    for arg in "$@"; do
        args="$args \"$arg\""
    done
    eval "$args"
}

# usage patch_rd "<command1>" "<command2>" ...
#    Supported commands:
#      exists ENTRY
#        Return 0 if ENTRY exists, else return 1
#      rm [-r] ENTRY
#        Remove ENTRY, specify [-r] to remove recursively
#      mkdir MODE ENTRY
#        Create directory ENTRY in permissions MODE
#      ln TARGET ENTRY
#        Create a symlink to TARGET with the name ENTRY
#      mv SOURCE DEST
#        Move SOURCE to DEST
#      add MODE ENTRY INFILE
#        Add INFILE as ENTRY in permissions MODE; replaces ENTRY if exists
#      extract [ENTRY OUT]
#        Extract ENTRY to OUT, or extract all entries to current directory
#      test
#        Test the cpio's status
#        Return value is 0 or bitwise or-ed of following values:
#        0x1:Magisk    0x2:unsupported    0x4:Sony
#      patch
#        Apply ramdisk patches
#        Configure with env variables: KEEPVERITY KEEPFORCEENCRYPT
#      backup ORIG
#        Create ramdisk backups from ORIG
#      restore
#        Restore ramdisk from ramdisk backup stored within incpio
#      sha1
#        Print stock boot SHA1 if previously backed up in ramdisk


get_flags
find_boot_image
abort(){
    ui_print "$1"
    exit
}

# make sure magiskboot exists
test ! -f /data/adb/magisk/magiskboot && abort "- Hmmm... Where is magiskboot binary?"

check_ramdisk(){
ui_print "- Checking ramdisk status"
if [ -e ramdisk.cpio ]; then
  magiskboot cpio ramdisk.cpio test
  STATUS=$?
else
  # Stock A only legacy SAR, or some Android 13 GKIs
  STATUS=0
fi
case $((STATUS & 3)) in
  0 )  # Stock boot
    ui_print "- Stock boot image detected"
    
    ;;
  1 )  # Magisk patched
    ui_print "- Magisk patched boot image detected"
    
    ;;
  2 )  # Unsupported
    ui_print "! Boot image patched by unsupported programs"
    abort "! Please restore back to stock boot image"
    ;;
esac
}

if [ ! -z "$BOOTIMAGE" ]; then
    ui_print "- Target boot image: $BOOTIMAGE"
    [ "$RECOVERYMODE" == "true" ] && ui_print "- Recovery mode is present, the script might patch recovery image..."
    mkdir -p "$TMPDIR/boot"
    if [ -c "$BOOTIMAGE" ]; then
        nanddump -f "$TMPDIR/boot/boot.img" "$BOOTIMAGE" || abort "! Unable to dump boot image"
        BOOTNAND="$BOOTIMAGE"
        BOOTIMAGE="$TMPDIR/boot/boot.img"
    else
        dd if="$BOOTIMAGE" of="$TMPDIR/boot/boot.img" || abort "! Unable to dump boot image"
    fi
    ui_print "- Unpack boot image"
    cd "$TMPDIR/boot" || exit 1
    magiskboot unpack boot.img
    check_ramdisk

# do your patch here

# Example:
# add test.rc as overlay.d/test.rc of ramdisk with permission flag 755
# patch_rd "add 755 overlay.d/test.rc test.rc"

# remove overlay.d/test.rc
# patch_rd "rm overlay.d/test.rc"

# remove overlay.d folder
# patch_rd "rm -r overlay.d"

# backup ramdisk_orig.cpio into ramdisk
# patch_rd "backup ramdisk_orig.cpio"

# restore backup of ramdisk.cpio
# after restoring backup, ramdisk.cpio will be like ramdisk_orig.cpio
# patch_rd "restore"


# repack boot image to new-boot.img

     ui_print "- Repack boot image"
     magiskboot repack boot.img || abort "! Unable to repack boot image"
     [ -e "$BOOTNAND" ] && BOOTIMAGE="$BOOTNAND"


# flash new boot image into $BOOTIMAGE

     ui_print "- Flashing new boot image"
     flash_image "$TMPDIR/boot/new-boot.img" "$BOOTIMAGE"
     case $? in
        1)
          abort "! Insufficient partition size"
          ;;

        2)

          # mediatek devices don't allow to flash boot image at boot image (from Android system). the only way is flashing through Custom Recovery or Fastboot

          ui_print "! $BOOTIMAGE is read-only"
          abort "! Unable to flash boot image"
          ;;
     esac
     ui_print "- All done!"
else
     ui_print "! Cannot detect target boot image"
fi