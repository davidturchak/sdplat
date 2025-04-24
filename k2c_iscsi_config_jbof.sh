#!/bin/bash

MIRROR_DEV_NAME='md1'
PHDD_DEV_NAME='md2'
LOCAL_DEV_NAME='md0'
STRIPS_DEV="/dev/$LOCAL_DEV_NAME"
STRIPS_PHDD="/dev/$PHDD_DEV_NAME"
MIRROR_DEV="/dev/$MIRROR_DEV_NAME"
IQN="iqn.2020-01.com.kaminario:$(hostname)"
TMP_PARTS_FILE='/tmp/parts'
PHDD_NAME_GCP='PersistentDisk'
PHDD_NAME_AWS='Elastic'
RAID_SPEED=999999
KERNEL_VERSION=''
IS_GCP=0

declare -a g_lu_devs
declare -a phdd_devices
declare -a phdd_num
declare -a boot_device
declare -a num_lus
declare -a configured_mirror

function main()
{
  log "========== Script Start =========="
  if [ -n "$1" ] && [ "$1" -gt 0 ]; then
    num_lus="$1"
  else
    log "Usage: $(basename $0) <num_lus>"
    exit 1
  fi

        is_gcp_dnode
  stop_iscsi
  remove_all_dm_delay_devices
  configure_nvme_devices
  config_raid_speed
  find_boot_devices

  # Find phdd devices
  if [ -z "$(/usr/sbin/dmidecode -s system-manufacturer | grep Microsoft)" ]; then
    find_phdd
  else
    find_phdd_azure
  fi

  # Create phdd raid (md2)
  if [ $phdd_num -gt 1 ]; then
    config_phdd_raid
  fi

  # Create local ssd raid (md0)
  if [ -z "$(uname -a | grep Ubuntu)" ]; then
    config_raid
  else
    config_raid_ubuntu
  fi

  # Create mirroring raid (md1)
  if [ $phdd_num -gt 0 ]; then
    config_mirroring
  fi

  if [ -z "$(cat /proc/mdstat | grep $MIRROR_DEV_NAME)" ]; then
    dev_to_configure=$STRIPS_DEV
  else
    dev_to_configure=$MIRROR_DEV
  fi

  if [ $num_lus -gt 1 ]; then
    if [ ! -z "$(lsblk -o serial | grep AWS)" ]; then
      create_partitions_AWS $num_lus $dev_to_configure
    else
      create_partitions $num_lus $dev_to_configure
    fi
  else
    g_lu_devs+="$dev_to_configure"
  fi
  config_dm_delay
  config_iscsi
}

function print_phdd_devices()
{
  if [ -z "$phdd_devices" ]; then
    phdd_devices=()
    phdd_num=0
    log "Did not find PHDD devices"
  else
    log "Found PHDD devices - ${phdd_devices[*]}"
  fi
}

function check_for_configured_mirror_raid()
{
  if [ $phdd_num -eq 0 ]; then
    return
  fi

  log "Checking for configured mirror raid"
  if [ $phdd_num -gt 1 ]; then
    configured_mirror=$(cat /proc/mdstat | grep "raid1\|$PHDD_DEV_NAME" | grep -v raid0 | grep -v Per | awk '{print $1}')
  else
    configured_mirror=$(cat /proc/mdstat | grep "raid1\|${phdd_devices[0]}" | grep -v Per | awk '{print $1}')
  fi

  if [ -z "$configured_mirror" ]; then
    log "Mirror raid is not configured yet"
  else
    log "Mirror raid is configured. Current name - $configured_mirror"
  fi
}

function find_phdd_azure()
{
  log "Looking for a PHDD devices on azure"

  phdd_devices=()
  phdd_num=0

  if [ -d "/dev/disk/azure/scsi1" ]; then
    for lun in $(ls -1 /dev/disk/azure/scsi1)
    do
      dev=$(readlink -f /dev/disk/azure/scsi1/$lun)
      phdd_devices+=($(echo "$dev" | sed -e "s/^\/dev\///"))
      ((phdd_num++))
    done
  fi

  print_phdd_devices
}

function find_boot_devices()
{
  bootpart=$(awk '{print $1}' <(awk '$7 == "/"' <(lsblk -l)))
  [ ${#bootpart} -eq 4 ] && boot_device=${bootpart::-1} || boot_device=${bootpart::-2}
}

function find_phdd()
{
  log "Looking for a PHDD devices"
  phdd_num=0
  phdd_devices=()
  for i in $(ls -C1 /sys/block/ | grep -v "loop\|md\|$boot_device");
  do
    if grep -q "$PHDD_NAME_GCP\|$PHDD_NAME_AWS" /sys/block/$i/device/model; then
      phdd_devices+=($i)
      ((phdd_num++))
    fi
  done

  print_phdd_devices
}

function config_mirroring()
{
  # Rename mirror raid if exists
  check_for_configured_mirror_raid
  configured_mirror_state=$(cat /proc/mdstat | grep $MIRROR_DEV_NAME | grep -v Per | awk '{print $3}')
  if [ "$configured_mirror_state" = "inactive" ] || [ ! -z  "$configured_mirror" ] && [ "$configured_mirror" != "$MIRROR_DEV_NAME" ]; then
    if [ ! -z "$configured_mirror" ]; then
      log "Removing /dev/$configured_mirror"
      /sbin/mdadm --stop /dev/$configured_mirror
    fi
    if [ $phdd_num -gt 1 ]; then
      /sbin/mdadm --assemble --update=name --name=1 $MIRROR_DEV $STRIPS_PHDD $STRIPS_DEV --run
      echo writemostly > /sys/block/$MIRROR_DEV_NAME/md/dev-$PHDD_DEV_NAME/state
    else
      /sbin/mdadm --assemble --update=name --name=1 $MIRROR_DEV /dev/${phdd_devices[0]} $STRIPS_DEV --run
      echo writemostly > /sys/block/$MIRROR_DEV_NAME/md/dev-${phdd_devices[0]}/state
    fi
  fi

  if [ -z "$(cat /proc/mdstat | grep $MIRROR_DEV_NAME)" ]; then
    config_new_mirroring
  else
    add_stripes_dev_to_mirroring
  fi
}

function remove_old_mirroring()
{
  log "Removing old Mirroring iscsi luns"
  for lun in $(seq 0 $(($num_lus - 1))); do
    log "Removing iSCSI lun $lun"
    echo "del 0" > /sys/kernel/scst_tgt/targets/iscsi/*/luns/mgmt
    echo "del_device lssd${lun}" > /sys/kernel/scst_tgt/handlers/vdisk_blockio/mgmt
    /sbin/mdadm --stop $MIRROR_DEV
  done
}

function rename_raid()
{
  local raid_ssds_tmp=$1[@]
  local configured_raid=$2
  local strips=$3
  local raid_ssds=("${!raid_ssds_tmp}")

  is_gcp_dnode
  if [ ! "$IS_GCP" -eq 1 ] ; then
    if [ ! -z "$configured_mirror" ] && [ ! -z "$(cat /proc/mdstat | grep $configured_mirror)" ]; then
      log "Removing /dev/$configured_mirror"
      /sbin/mdadm --stop /dev/$configured_mirror
    fi
  fi

  log "Removing /dev/$configured_raid"
  /sbin/mdadm --stop /dev/$configured_raid

  if [ ! $? -eq 0 ] ; then
    log "Failed removing the raid device, removing mirror device first"
    if [ ! -z "$configured_mirror" ] && [ ! -z "$(cat /proc/mdstat | grep $configured_mirror)" ]; then
      log "Removing /dev/$configured_mirror"
      /sbin/mdadm --stop /dev/$configured_mirror
    fi

    log "Removing /dev/$configured_raid"
    /sbin/mdadm --stop /dev/$configured_raid
  fi

  sleep 3
  /sbin/mdadm --assemble --update=name --name=0 $strips ${raid_ssds[@]}
  sleep 3
}

function config_new_mirroring()
{
  if [ $phdd_num -gt 1 ]; then
    log "Configuring RAID-1 between $STRIPS_DEV and $STRIPS_PHDD SSDs"
    echo y | /sbin/mdadm -C $MIRROR_DEV -l raid1 --force -n 2 $STRIPS_DEV --write-mostly $STRIPS_PHDD --assume-clean 2>/dev/null
    log "Configuring RAID-1 between $STRIPS_DEV and $STRIPS_PHDD SSDs - done"
  else
    log "Configuring RAID-1 between $STRIPS_DEV and ${phdd_devices[0]} SSDs"
    echo y | /sbin/mdadm -C $MIRROR_DEV -l raid1 --force -n 2 $STRIPS_DEV --write-mostly /dev/${phdd_devices[0]} --assume-clean 2>/dev/null
    log "Configuring RAID-1 between $STRIPS_DEV and ${phdd_devices[0]} SSDs - done"
  fi
}

function add_stripes_dev_to_mirroring()
{
  if [ ! -z "$(/sbin/mdadm -D /dev/md1 | grep '/dev/md0\|/dev/md/0' | egrep 'active sync')" ]; then
    log "All devices seems to be present in $MIRROR_DEV"
    return
  fi

  log "Adding $STRIPS_DEV to RAID-1"
  retries=6
  while [ ${retries} -gt 0 ];
    do
      /sbin/mdadm --manage $MIRROR_DEV --add $STRIPS_DEV >/dev/null 2>&1
      RESULT=$?
      if [ $RESULT -eq 0 ]; then
          break
      fi
      log "Raid 1 is not up yet, waiting..."
      retries=$((retries - 1))
      sleep 10
    done
  if [ $RESULT -eq 0 ]; then
    log "Adding $STRIPS_DEV to RAID-1 - Done."
  else
    log "Adding $STRIPS_DEV to RAID-1 - Failed!."
  fi
}

function remove_all_dm_delay_devices() {
  log "Looking for dm-delay devices to remove..."

  mapfile -t dm_delay_devs < <(dmsetup ls --target delay | awk '{print $1}')

  if [[ ${#dm_delay_devs[@]} -eq 0 ]]; then
    log "No dm-delay devices found."
    return
  fi

  for dev in "${dm_delay_devs[@]}"; do
    log "Removing dm-delay device: $dev"
    dmsetup remove "$dev"
  done
}

function stop_iscsi()
{
  log "Stopping iSCSI"
  if [ -e /sys/kernel/scst_tgt/targets/iscsi/enabled ]; then
          echo 0 > /sys/kernel/scst_tgt/targets/iscsi/enabled
  fi
  sleep 1
  pkill iscsi-scstd
  sleep 1
  /sbin/modprobe -r iscsi-scst scst_vdisk scst
  log "iSCSI successfully stopped"
}



function configure_nvme_devices()
{
  echo 88 > /sys/module/nvme_core/parameters/io_timeout
  echo 0 > /sys/module/nvme_core/parameters/max_retries
}

function config_raid_speed()
{
  log "Configuring RAID speed limit to $RAID_SPEED"
  echo $RAID_SPEED >  /proc/sys/dev/raid/speed_limit_min
  echo $RAID_SPEED >  /proc/sys/dev/raid/speed_limit_max
  log "RAID speed limit Configured successfully"
}

function config_phdd_raid()
{
  log "Configuring PHDD RAID-0"

  if [ ! -z "$(cat /proc/mdstat | grep $PHDD_DEV_NAME)" ]; then
    log "PHDD raid has already been configured"
    return
  fi

  local raid_ssds=($(ls -1 /dev/* | grep $(echo "${phdd_devices[@]}" | sed "s/ /\\\|/g")))

  # After reboot md name is changing, rename it again
  local configured_phdd=$(cat /proc/mdstat | grep $(echo "${phdd_devices[@]}" | sed "s/ /\\\|/g") | grep -v Per | awk '{print $1}')
  if [ ! -z "$configured_phdd" ] && [ "$configured_phdd" != "$PHDD_DEV_NAME" ]; then
    # change the names of existing phdd raid
    log "Found PHDD raid device - $configured_phdd, renaming ..."

    check_for_configured_mirror_raid
    if [ -z "$configured_mirror" ]; then
      configured_mirror=$(cat /proc/mdstat | grep $configured_phdd | grep -v raid0 | grep -v Per | awk '{print $1}')
    fi

    rename_raid raid_ssds "$configured_phdd" "$STRIPS_PHDD"
    log "PHDD RAID renamed successfully"
  else
    # Create new md2
    log "Configuring new PHDD RAID"
    for phdd_dev in ${phdd_devices[@]}; do
      dd if=/dev/zero of=/dev/$phdd_dev bs=1M count=1 >/dev/null 2>&1
    done

    echo y | /sbin/mdadm -C "$STRIPS_PHDD" -l raid0 --force -n $phdd_num ${raid_ssds[@]} 2>/dev/null
    dd if=/dev/zero of=$STRIPS_PHDD bs=1M count=1 >/dev/null 2>&1
    log "PHDD RAID configured successfully"
  fi

  for i in $(/sbin/mdadm -D /dev/md2 | grep 'dev/s' | tr '/' ' ' | awk '{print $8}'); do
    echo mq-deadline > /sys/block/$i/queue/scheduler
  done
}

function config_raid_ubuntu()
{
  log "Configuring local devices RAID-0 on ubuntu"
  local configured_raid
  local raid_ssds
  if [ $phdd_num -gt 0 ]; then
    raid_ssds=($(ls -1 /dev/nvme*n* | grep -v "$boot_device" | grep -v $(echo "${phdd_devices[@]}" | sed "s/ /\\\|/g")))
  else
    raid_ssds=($(ls -1 /dev/nvme*n* | grep -v "$boot_device"))
  fi

  configured_raid=$(cat /proc/mdstat | grep raid0 | grep -v $PHDD_DEV_NAME | grep -v Per | awk '{print $1}')
  if [ -z "$configured_raid" ]; then
    config_raid
    return
  else
    log "Local devices RAID-0 has already been configured"
  fi

  # After zone outage the md names are changed, we need to rename according to our convention
  if [ "$configured_raid" != "$LOCAL_DEV_NAME" ]; then
    log "Found local raid devices - $configured_raid, renaming them..."
    check_for_configured_mirror_raid
    rename_raid raid_ssds "$configured_raid" "$STRIPS_DEV"
    log "Local devices RAID configured successfully"
  fi
}

function config_raid()
{
  local raid_ssds
  if [ "$phdd_num" -gt 0 ]; then
    raid_ssds=($(ls -1 /dev/nvme*n* | grep -v "$boot_device" | grep -v $(echo "${phdd_devices[@]}" | sed "s/ /\\\|/g")))
  else
    raid_ssds=($(ls -1 /dev/nvme*n* | grep -v "$boot_device"))
  fi
  local num_ssds=${#raid_ssds[@]}

  log "Configuring local RAID-0 on $num_ssds SSDs"
  for dev in $(egrep -o '^md[0-9]+' /proc/mdstat | grep -v "$MIRROR_DEV_NAME\|$PHDD_DEV_NAME"$); do
    log "Removing /dev/$dev"
    /sbin/mdadm --manage --stop /dev/$dev
  done

  for dev in ${raid_ssds[@]}; do
    dd if=/dev/zero of=$dev bs=1M count=1 >/dev/null 2>&1
  done

  rm -f "$STRIPS_DEV"
  echo yes | /sbin/mdadm -C "$STRIPS_DEV" -l raid0 --force -n $num_ssds ${raid_ssds[@]} 2>/dev/null
  dd if=/dev/zero of=$STRIPS_DEV bs=1M count=1 >/dev/null 2>&1
  log "Local RAID-0 on $num_ssds SSDs configured successfully"
}

function create_partitions_AWS()
{
  local num=$1
  local partition_dev=$2

  echo "Creating $num partitions"
  size_sectors=$(fdisk -l  $partition_dev 2>/dev/null | awk '$1 == "Disk" && $8 == "sectors" {print $7}')
  let size_mib=(size_sectors-2048)/2048
  let part_size_mib=size_mib/$num

  echo $size_sectors $size_mib $part_mib
  /sbin/parted $partition_dev --script mklabel gpt
  for  part_num in `seq 1 $num` ; do
    part_name="${MIRROR_DEV}p${part_num}"
    g_lu_devs+=("$part_name")
    let start=1+\(part_num-1\)*part_size_mib
    let end=start+part_size_mib
    /sbin/parted $partition_dev --script mkpart primary ext4 ${start}MiB ${end}MiB
  done
}

function create_partitions()
{
  local num_of_partitions=$1
  local disk=$2

  # Get the size of the disk in bytes:
  disk_size=$(blockdev --getsize64 ${disk})

  # Convert disk size form bytes to gigabytes
  disk_size_in_gb=$(echo "scale=2; $disk_size/1024/1024/1024" | bc)

  # Lets make disk sizer as integer
  int_value=$(printf "%.0f" $disk_size_in_gb)

  # Calculate the size of each partition in gb
  partition_size=$((int_value/num_of_partitions))

  log "Going to create ${num_of_partitions} partitions in size of ${partition_size}GB"

  # Create a partition table on the disk
  /sbin/parted --script ${disk} mklabel gpt

  # Create 9 equal-sized partitions
  /sbin/parted --script ${disk} mkpart primary 0% ${partition_size}GB
  for i in $(seq 2 1 $num_of_partitions)
  do
  start=$((partition_size * (i-1)))
  end=$((partition_size * (i)))
  /sbin/parted -s ${disk} mkpart primary ${start}GB ${end}GB
  part_name="${disk}p$(($i-1))"
  g_lu_devs+=("$part_name")
  done

  part_name="${disk}p$i"
  g_lu_devs+=("$part_name")

  # Reload the partition table
  partprobe
  /sbin/parted -s ${disk} print

  log "Disk ${disk} has been partitioned into $num_of_partitions equal-sized partitions."
}

function config_dm_delay()
{
log "Wrapping devices in dm-delay (0ms read/write latency)..."
local -i dev_id=0
for dev in "${g_lu_devs[@]}"; do
    base_dev=$(basename "$dev")
    delayed_dev="/dev/mapper/${base_dev}_delayed${dev_id}"
    # Only create dm-delay if not already present

    if [ ! -e "$delayed_dev" ]; then
        dmsetup create ${base_dev}_delayed${dev_id} --table "0 $(blockdev --getsz $dev) delay $dev 0 0"
        if [ $? -eq 0 ]; then
            log "Created $delayed_dev with 0ms read/write delay"
            # Update array to point to the delayed device
            g_lu_devs=( "${g_lu_devs[@]/$dev/$delayed_dev}" )
            ((devid++))
        else
            log "Failed to create dm-delay for $dev"
            exit
        fi
    fi
done
}

function config_iscsi()
{
  log "Configuring iSCSI"

  /sbin/modprobe scst
  /sbin/modprobe scst_vdisk
  /sbin/modprobe iscsi-scst
  /sbin/iscsi-scstd &
  sleep 4
  echo "add_target $IQN" > /sys/kernel/scst_tgt/targets/iscsi/mgmt
  sleep 1
  echo 1 > /sys/kernel/scst_tgt/targets/iscsi/enabled
  echo 1 > /sys/kernel/scst_tgt/targets/iscsi/$IQN/enabled
  echo 90 > /sys/kernel/scst_tgt/targets/iscsi/$IQN/NopInTimeout
  echo 90 > /sys/kernel/scst_tgt/targets/iscsi/$IQN/RspTimeout
  echo 30 > /sys/kernel/scst_tgt/targets/iscsi/$IQN/NopInInterval

  if [ ! "$IS_GCP" -eq 1 ] ; then
    # we will configure the FirstBurstLength to 256K to improve performance for 1M large writes.
    log "configure D-node FirstBurstLength to 256K"
    echo 262144 > /sys/kernel/scst_tgt/targets/iscsi/$IQN/FirstBurstLength
  fi
  local -i lun=0
  for dev_name in "${g_lu_devs[@]}"; do
    log "Adding iSCSI lun $lun: $dev_name"
    echo "add_device lssd${lun} write_through=1;nv_cache=1;blocksize=4096;rotational=0;filename=$dev_name" > /sys/kernel/scst_tgt/handlers/vdisk_blockio/mgmt
    echo "add lssd${lun} $lun" > /sys/kernel/scst_tgt/targets/iscsi/$IQN/luns/mgmt
    ((lun++))
  done
  log "iSCSI configured successfully"
}

function is_gcp_dnode() {
        KERNEL_VERSION=`uname -r`
        if [ $KERNEL_VERSION == "4.15.0-1040-gcp" ] ; then
                log "setting flag for GCP dnode"
                IS_GCP=1
        fi
}

function log() {
  echo [$(date +"%Y/%m/%d-%T.%6N")] $1
  logger $1
}

main "$@"
