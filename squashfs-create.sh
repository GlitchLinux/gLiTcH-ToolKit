# CREATE FILESYSTEM.SQUASHFS FROM /

#!/bin/bash

sudo mksquashfs / /filesystem.squashfs \
  -comp xz -Xdict-size 100% -b 1M -noappend \
  -wildcards -ef /dev/stdin <<EOF
dev/*
proc/*
sys/*
tmp/*
run/*
mnt/*
media/*
lost+found
var/cache/*
var/tmp/*
var/log/*
var/lib/apt/lists/*
var/lib/dhcp/*
home/*
filesystem.squashfs
EOF
