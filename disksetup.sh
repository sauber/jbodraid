#!/bin/sh

# Convert a list of disk sizes into partition tables for each disk.
# Example. Input is
#  ad0 5
#  ad1 4
#  ad2 6
#  ad3 3
# Middle result is
#  root, 1: ad0 ad2
#  data1, 3: ad0 ad1 ad2 ad3
#  data2, 1: ad0 ad1 ad2
#  scratch 1: ad2
# End result:
#  ---- ----  - - - - - - - -
#  Disk Size: a b c d e f g h
#  ---- ----  - - - - - - - -
#   ad0    5: 1 0 5 3 1
#   ad1    4: 0 0 4 3 1
#   ad2    6: 1 0 6 3 1 0 0 1
#   ad3    3: 0 0 3 3
#  ---- ----  - - - - - - - -

# 1GB = 1024*1024*1024/512 sectors
rootvolsize=2097152

# List of all disks available
#
disklist () {
  #disks=`egrep '(ad|da)[0-9]:' /var/run/dmesg.boot | awk '{print $1}' | sort | uniq`
  # Testing
  disks="ad0 ad1 ad2 ad3"
}

# Identify where / is currently mounted from. It's the current rootdisk.
#
rootdisk () {
  #rootdisk=`mount | grep ' / ' | sed 's;/dev/\([a-z]*[0-9]*\).*$;\1;'`
  # Testing
  rootdisk=ad0
}

# Get total size of all disks
#
disksize () {
  disklist
  for d in $disks ; do
    #sectors=`diskinfo $disk | awk '{print $4}'`
    if   [ "$d" = "ad0" ] ; then
      sectors=3829760
    elif [ "$d" = "ad1" ] ; then
      sectors=3084288
    elif [ "$d" = "ad2" ] ; then
      sectors=3698688
    elif [ "$d" = "ad3" ] ; then
      sectors=3270656
    fi
    eval ${d}_size=$sectors
    eval echo Sectors for $d is \$${d}_size
  done
}

# Identify largest disk not used
#
largestnotused () {
  x=$1
  tmpfile=/tmp/.delme.$$
  ( for d in $disks ; do
      if [ "$d" != "$x" ] ; then
        eval echo \$${d}_size $d
      fi
    done ) | sort -n | tail -1 | awk '{print $2}' > $tmpfile
  largedisk=`cat $tmpfile`
  rm $tmpfile
  #echo Largest disk excluding $x is $largedisk
}

# Remove disk space from disk size
extractspace () {
  set -x
  disk=$1
  size=$2
  eval currentsize=\$${disk}_size
  eval ${disk}_size=`expr $currentsize - $size`
}

# Find list of disks for root volume
#
newrootdisks () {
  disklist
  disksize
  rootdisk
  largestnotused $rootdisk
  root1=$largedisk
  largestnotused $rootprimary
  root2=$largedisk
  echo root1=$root1
  echo root2=$root2
  extractspace $root1 $rootvolsize
  extractspace $root2 $rootvolsize
}

# Find the disk with the least amount of free space. Return the size.
#
smallestdisk () {
  tmpfile=/tmp/.delme.$$
  ( for d in $disks ; do
      eval currentsize=\$${disk}_size
      if [ "$currentsize" -gt 0 ] ; then
        echo $currentsize $d
      fi
  done ) | sort -n | head -1 | awk '{print $1}' > $tmpfile
  slicesize=`cat $tmpfile`
  rm $tmpfile
}

# Number of disks that still has free space
#
numfreedisks () {
  tmpfile=/tmp/.delme.$$
  ( for d in $disks ; do
      eval currentsize=\$${disk}_size
      if [ "$currentsize" -gt 0 ] ; then
        echo $currentsize $d
      fi
  done ) | wc -l > $tmpfile
  numdisks=`cat $tmpfile`
  rm $tmpfile
}

# Find disks for raid volumes for data
#
newdatadisks () {
  numfreedisks
  while [ "$numdisks" -gt 1 ] ;  do
    echo Number of free disks is $numdisks
    sleep 2
  done
}

# Find out which disks to install rootvol on
newrootdisks

# Given the root disks identified, layout remaining redundant disks for
# raid volumes for data.
newdatadisks
