# Take a list of disk sizes, and produce a redundant layout with
# maximum capacity
# Soren, May 2009
# Original script my Magnus Svavarsson

# Program flow
#  - Read in disk sizes
#  - Put root on two largest disks, slice a
#  - Slice b is for swap, set it to 0
#  - Slice c is whole disk
#  - Slice d, e, f, g is for raid volumes
#  - Slice h is for non-raid left over space

# Tip:
#  - To pass an argument:
#      nawk -v fil=4 'BEGIN{print fil}'

# TODO:
#  - Slices in same volume on same letter where possible
#  - Handle blocks and gigabytes
#  - Handle swap

{
  # Each line of input is: diskname  disksize
  # Initialize whole disk table for each disk
  diskslice[$1,"a"]=0;     # Root
  diskslice[$1,"b"]=0;     # Swap
  diskslice[$1,"c"]=$2;    # Overlap
  diskslice[$1,"d"]=0;     # Data
  diskslice[$1,"e"]=0;     # Data
  diskslice[$1,"f"]=0;     # Data
  diskslice[$1,"g"]=0;     # Data
  diskslice[$1,"h"]=$2-16; # Free space, first 16 sectors for bootblock
  diskname[NR]=$1;         # Name of disk by position
  DiskNr=NR;               # Total number of disks available
}

END{
  # Default size of root disk is 1GB
  if ( rootsize == "" ) rootsize=1024*1024*1024/512;
  # Default size of swap disk is 0
  if ( swapsize == "" ) swapsize=0;
  # Generate initial cache of free disk space
  diskfreesort();
  # Assign disks to root, data and swap volumes
  rootdisks();
  datadisks();
  swapdisks();
  # Print out the resulting disk slice table
  printslicetable();
  # Print out volume layout
  printrootvolume();
  printswapvolume();
  printdatavolumes();
  printfreevolume();
}

# Maintain a list of disks that still has free space in array sorted[].
# For ZFS there must be at least 64 MB free on a slice.
#
function diskfreesort(forswap,     free,i,d,j,m,n,e) {
  # Create a list of disks that has free space.
  # Erase old sorted list.
  for (i in diskname) {
    delete sorted[i];
    d=diskname[i];
    minsize=64*1024*1024/512
    if ( diskslice[d,"h"] > minsize ) {     # h must have enough free space
      # Check that at least one slice is free
      if ( diskslice[d,"d"] == 0 ) free[d]=diskslice[d,"h"];
      if ( diskslice[d,"e"] == 0 ) free[d]=diskslice[d,"h"];
      if ( diskslice[d,"f"] == 0 ) free[d]=diskslice[d,"h"];
      if ( diskslice[d,"g"] == 0 ) free[d]=diskslice[d,"h"];
    }
  }

  # Find largest remaining disk
  i=0;
  for ( j in diskname ) {
    m=0; # Maxsize
    n=""; # Maxdisk
    for ( e in free ) {
      if ( free[e] > m ) {
        m=free[e]; 
        n=e;
      }
    }
    if ( m > 0 ) {
      i++;
      sorted[i]=n;
      delete free[n];
    }
  }
}

# Take space from free slice h and assign to named or next available slice.
# Return the name of the slice that space is assigned to
#
function setslice(disk,size,slice) {
  # If preferred slice is specified, confirm that it is available
  if ( slice != "" ) {
    if ( diskslice[disk,slice] != 0 ) {
      #printf("Disk %s slice %s size %s not available\n", disk, slice, diskslice[disk,slice]);
      slice="";
    }
  }
  # If no slice is specified, or it is not free, find next available one
  if ( slice == "" ) {
    if ( diskslice[disk,"g"] == 0 ) slice="g";
    if ( diskslice[disk,"f"] == 0 ) slice="f";
    if ( diskslice[disk,"e"] == 0 ) slice="e";
    if ( diskslice[disk,"d"] == 0 ) slice="d";
  }
  # In case no slice is found
  if ( slice == "" ) return "";

  #printf("Slice %s before: %s\n", slice, diskslice[disk,slice]);
  #printf("Slice %s before: %s\n",   "h", diskslice[disk,  "h"]);

  diskslice[disk,slice] = size;
  diskslice[disk,"h"] -= size;

  #printf("Slice %s after : %s\n", slice, diskslice[disk,slice]);
  #printf("Slice %s after : %s\n",   "h", diskslice[disk,  "h"]);

  # Every time disk space is assigned, update the free space table
  diskfreesort();

  return slice;
}

# Names of two largest disks
#
function rootdisks() {
  #printf("Root disk1: %s\n", sorted[1]);
  #printf("Root disk2: %s\n", sorted[2]);
  rootdisk[1]=sorted[1];
  rootdisk[2]=sorted[2];
  setslice(rootdisk[1], rootsize, "a");
  setslice(rootdisk[2], rootsize, "a");
}

# Create Raid or Mirror volumes for data
function datadisks(    numslices,maxsize,maxslices,maxslicesize,volnr,d,f,a,i,v,p,s,t) {
  # While there are at least 2 free disks
  volnr=1;
  while ( length(sorted)>=2 && freespace()-swapsize>1 ) {
    # Find combination of disks giving larges volume size
    numslices=length(sorted);
    maxsize=0;
    maxslices=0;
    s=freespace(); # Available free space on disks
    for (n=numslices; n>=2; n--) {
      #printf("Volume %s numslices %s\n", volnr, n);
      d=sorted[n];        # Name of smallest disk
      f=diskslice[d,"h"]; # Size of smallest disk
      a=(n-1)*f;          # Total available space on raid volume
      # Here we check if there is still enough space
      # available for swap. If not, decrease slicesize (f)
      # until there is.
      # Example:
      #   Freespace = 51
      #   Volsize = 40
      #   Swapsize = 20
      #   Too much = 20+40-51 = 11
      if ( s-(n*f) < swapsize ) {
        # How much disks space too much will be taken
        t=swapsize+(n*f)-s;
        # How much per volume
        t=t/n;
        # Round up to nearest whole unit
        if ( t != int(t) ) {
          t=int(t+1);
        }
        #printf("Volume %s using size %s is %s too many\n", volnr, f, t);
        # Recalculate sizes
        f-=t;
        a=(n-1)*f;
      }
      # XXX: I'm in doubt here if smaller number of slices gives
      #      gives overall better disk space than higher number of
      #      disk slices.
      #      To prefer smaller number of slices, chang to >=
      if ( a > maxsize ) {
        maxsize=a;
        maxslices=n;
        maxslicesize=f;
      }
    }
    # maxslices holds the number of slices to maximize volume space
    # assign the space
    d=sorted[maxslices];        # Name of smallest disk
    #f=diskslice[d,"h"];        # Size of smallest disk
    f=maxslicesize;             # Slice size, still leaving enough free space
    #printf("Using disk %s of size %s as base.\n", d, f);
    for (i=1; i<=maxslices; i++) {
      v[i]=sorted[i];
      #printf("Adding disk: %s\n",v[i]);
      
    }
    p=""; # No preferred slice
    for (i=1; i<=maxslices; i++)  {
      slice=setslice(v[i],f,p);
      if ( p == "" ) p=slice; # Try to use same slice for all disks
      datadisk[volnr,v[i]]=sprintf("%s%s",v[i],slice);
      #printf("Volume %s disk %s slice %s size %s\n",volnr,v[i],slice,f);
    }
    datadisk[volnr,"numslices"]=maxslices;
    datadisk[volnr,"slicesize"]=f;
    datadisk[volnr,"volsize"]=(maxslices-1)*f;
    if ( maxslices  > 2 ) datadisk[volnr,"type"]="raidz1";
    if ( maxslices == 2 ) datadisk[volnr,"type"]="mirror";
    DataNr=volnr;
    volnr++;
  }
}

# Assign disks to swap.
# XXX: Right it's in no particular order. Perhaps a better way exist.
#
function swapdisks(     s,d,i,f,t) {
  #s=swapsize;  # Swap space still not assigned
  #i=1;         # Disk number in sorted list
  #while ( s > 0 ) {
  #  d=sorted[i];
  #  f=diskslice[d,"h"];
  #  if ( f >= s ) {
  #    # It has same or more disk space than we need
  #    printf("Swap, taking %s from %s\n", s, d);
  #    setslice(d,s,"b");
  #    s=0;
  #  } else {
  #    # It has less than we need
  #    printf("Swap, taking %s from %s\n", f, d);
  #    setslice(d,f,"b");
  #    s-=f;
  #  }
  #  i++;
  #}
  s=swapsize;  # Swap space still not assigned
  for (i in diskname) {
    if ( s > 0 ) {
      d=diskname[i];
      f=diskslice[d,"h"];
      if ( f > 0 ) {
        if ( f >= s ) t=s;
        if ( f <  s ) t=f;
        #printf("Swap, taking %s from %s\n", t, d);
        setslice(d,t,"b");
        s-=t;
      }
    }
  }
}

# Calculate total size of free space
#
function freespace(     i,d,f,volsize) {
  for (i in diskname){
    d=diskname[i];
    f=diskslice[d,"h"];
    if ( f> 0 ) {
      volsize+=f;
    }
  }
  return volsize;
}

# Pretty print the slice table
# XXX: Sort disks by same order as input
#
function printslicetable(     i,d) {
  print "DISK SLICE TABLE";
  printf("Disk name,  %4s %4s %4s %4s %4s %4s %4s %4s\n",
         "a","b","c","d","e","f","g","h");
  for (i in diskname){
    d=diskname[i];
    printf("Disk %4s,  %4d %4d %4d %4d %4d %4d %4d %4d\n",
      d,
      diskslice[d,"a"],
      diskslice[d,"b"],
      diskslice[d,"c"],
      diskslice[d,"d"],
      diskslice[d,"e"],
      diskslice[d,"f"],
      diskslice[d,"g"],
      diskslice[d,"h"]);
  }
  print "";
}

# Pretty print the root volume layout
#
function printrootvolume() {
  print "ROOT VOLUME TABLE";
  printf("  root, layout=gmirror, numslice=2, slicesize=%s, volsize=%s\n",
         rootsize, rootsize);
  #printf("    %sa\n", rootdisk[1]);
  #printf("    %sa\n", rootdisk[2]);
  printf("        slices=%sa %sa\n", rootdisk[1], rootdisk[2]);
  print "";
}

# Pretty print the data volume layout
#
function printdatavolumes(    v,i,d,l) {
  print "DATA VOLUME TABLE";
  for (v=1;v<=DataNr; v++) {
    printf("  data%s, layout=%s, numslice=%s, slicesize=%s, volsize=%s\n",
      v,
      datadisk[v,"type"],
      datadisk[v,"numslices"],
      datadisk[v,"slicesize"],
      datadisk[v,"volsize"]);
    l="";
    for (i in diskname) {
      d=diskname[i];
      if ( datadisk[v,d] != "" ) {
        #printf("    %s\n", datadisk[v,d]);
        l=l sprintf("%s ", datadisk[v,d]);
      }
    }
    printf("         slices=%s\n",l);
  }
  print "";
}

# Pretty print the volume made up of left over space
#
function printfreevolume(     d,i,f,l,volsize,numslices) {
  volsize=freespace();
  # Count number of free slices
  for (i in diskname){
    d=diskname[i];
    f=diskslice[d,"h"];
    if ( f> 0 ) {
      numslices++;
    }
  }
  print "FREE VOLUME TABLE";
  printf("  root, layout=concat, numslice=%s slicesize=*, volsize=%s\n",
         numslices, volsize);
  for (i in diskname){
    d=diskname[i];
    f=diskslice[d,"h"];
    if ( f> 0 ) {
      #printf("    %sh\n", d);
      l=l sprintf("%sh ", d);
    }
  }
  printf("        slices=%s\n",l);
  print "";
}

# Pretty print the swap volume
#
function printswapvolume(     numslices,i,d,f,l){
  # Count number of slices
  for (i in diskname){
    d=diskname[i];
    f=diskslice[d,"b"];
    if ( f> 0 ) {
      numslices++;
    }
  }
  print "SWAP VOLUME TABLE";
  printf("  swap, layout=concat, numslice=%s slicesize=*, volsize=%s\n",
         numslices, swapsize);
  for (i in diskname){
    d=diskname[i];
    f=diskslice[d,"b"];
    if ( f> 0 ) {
      #printf("    %sb\n", d);
      l=l sprintf("%sb ", d);
    }
  }
  printf("        slices=%s\n",l);
  print "";
}
