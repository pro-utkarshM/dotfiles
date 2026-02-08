#!/usr/bin/env bash
set -e

echo "== Hybrid Swap Setup (ZRAM 8G + Swapfile 16G) =="

# ---- CONFIG ----
ZRAM_SIZE=$((8 * 1024 * 1024 * 1024))
SWAPFILE_SIZE=16G
SWAPDIR=/swap
SWAPFILE=$SWAPDIR/swapfile

echo "[1/7] Disable systemd zram generator if present"
systemctl mask systemd-zram-setup@zram0.service 2>/dev/null || true

echo "[2/7] Setup ZRAM"

swapoff -a || true
modprobe zram || true

echo zstd > /sys/block/zram0/comp_algorithm
echo $ZRAM_SIZE > /sys/block/zram0/disksize

mkswap /dev/zram0 >/dev/null
swapon /dev/zram0

echo "[3/7] Setup disk swapfile (Btrfs safe)"

rm -f /swapfile || true

mkdir -p $SWAPDIR
chattr +C $SWAPDIR || true

fallocate -l $SWAPFILE_SIZE $SWAPFILE
chmod 600 $SWAPFILE

mkswap $SWAPFILE >/dev/null
swapon $SWAPFILE

echo "[4/7] Persist swapfile"

grep -q "$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap defaults 0 0" >> /etc/fstab

echo "[5/7] Swappiness tuning"

echo "vm.swappiness=80" > /etc/sysctl.d/99-swappiness.conf
sysctl --system >/dev/null

echo "[6/7] Create ZRAM systemd service"

cat >/etc/systemd/system/zram.service <<EOF
[Unit]
Description=Manual ZRAM setup
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "modprobe zram && echo zstd > /sys/block/zram0/comp_algorithm && echo $ZRAM_SIZE > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon /dev/zram0"
ExecStop=/sbin/swapoff /dev/zram0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zram.service

echo "[7/7] Done."

echo
echo "Final swap status:"
swapon --show
free -h

echo
echo "Hybrid swap configured successfully."
