#!/usr/bin/env bash

# Deploy Arch Linux Unattended
# Example script for virtual environments
# https://github.com/honze-net/dalu
# https://wiki.archlinux.org/index.php/installation_guide

# Enable error handling.
set -euxo pipefail

# Enable logging.
LOGFILE="install.log"
exec &> >(tee -a "$LOGFILE")

# Configuration options. All variables should be exported, so that they will be availabe in the arch-chroot.
export KEYMAP="de-latin1"
export LANG="de_DE.UTF-8"
export LOCALE="de_DE.UTF-8 UTF-8"
export TIMEZONE="Europe/Berlin"
export COUNTRY="Germany"
export HOSTNAME="arc"
export USERNAME="user"
export PASSWORD=$USERNAME # It is not recommended to set production passwords here.
export DISK="/dev/sda"

# Find and set mirrors. This mirror list will be automatically copied into the installed system.
pacman -Sy --needed --noconfirm reflector
reflector --country $COUNTRY --age 12 --latest 10 --sort rate --protocol https --save /etc/pacman.d/mirrorlist

# Use MBR, partition the whole disk with one partition, bootable, no swap.
parted -a optimal $DISK mklabel msdos mkpart primary 0% 100% set 1 boot on 

# Get the "/dev/..." name of the first partition, format it and mount.
export ROOTPARTITION=$(ls $DISK*1*) 
mkfs.ext4 $ROOTPARTITION -L root
mount $ROOTPARTITION /mnt

# Install base files and update fstab.
pacstrap -K /mnt base linux linux-firmware
genfstab -U /mnt >> /mnt/etc/fstab

# Extend logging to persistant storage.
cp "$LOGFILE" /mnt/root/
exec &> >(tee -a "$LOGFILE" | tee -a "/mnt/root/$LOGFILE")

# This function will be executed inside the arch-chroot.
archroot() {
  # Enable error handling again, as this is technically a new execution.
  set -euxo pipefail

  # Set and generate locales.
  echo "LANG=$LANG" >> /etc/locale.conf
  #echo "KEYMAP=$KEYMAP" >> /etc/vconsole.conf
  sed -i "/$LOCALE/s/^#//" /etc/locale.gen # Uncomment line with sed
  locale-gen

  # Set time zone and clock.
  ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
  hwclock --systohc

  # Set hostname.
  echo "$HOSTNAME" > /etc/hostname

  # This is optional.
  # mkinitcpio -P
  
  # Install boot loader.
  pacman -S --needed --noconfirm grub
  grub-install $DISK
  grub-mkconfig -o /boot/grub/grub.cfg

  # Install and enable network manager.
  pacman -S --needed --noconfirm networkmanager
  systemctl enable NetworkManager

  # Install and configure sudo.
  pacman -S --needed --noconfirm sudo
  sed -i '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' /etc/sudoers # Uncomment line with sed

  # Create a new user and add it to the wheel group.
  useradd -m -G wheel $USERNAME
  echo $USERNAME:$PASSWORD | chpasswd
  passwd -e $USERNAME # Force user to change password at next login.
  passwd -dl root # Delete root password and lock root account.

  # Fix too low entropy, that can cause a slow system start.
  pacman -S --needed --noconfirm haveged
  systemctl enable haveged

  # Install and configure the desktop environment.
  pacman -S --needed --noconfirm gnome gnome-tweaks
  systemctl enable gdm
  sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'de')]"
  #sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
  sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"

  #sudo -u $USERNAME curl -o /home/$USERNAME/pexels-photo-2387793.jpeg "https://images.pexels.com/photos/2387793/pexels-photo-2387793.jpeg"
  #sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.background picture-uri "/home/$USERNAME/pexels-photo-2387793.jpeg"

  # Install git as prerequisite for the next steps.
  pacman -S --needed --noconfirm git base-devel cargo

  # Install an AUR helper.
  cd /tmp
  sudo -u $USERNAME git clone https://aur.archlinux.org/paru-bin.git
  cd paru-bin
  sudo -u $USERNAME makepkg -sri --noconfirm
  cd .. && rm -R paru-bin
  sed -i '/^#Color/s/#//' /etc/pacman.conf # Uncomment line with sed

  # Check if a hypervisor is used and install the corresponding guest software.
  pacman -S --needed --noconfirm dmidecode 
  if [[ $(dmidecode -s system-product-name) == *"VirtualBox"* ]]; then
    pacman -S --needed --noconfirm linux-headers virtualbox-guest-utils
    systemctl enable vboxservice
  fi

  if [[ $(dmidecode -s system-product-name) == *"VMware Virtual Platform"* ]]; then
    pacman -S --needed --noconfirm linux-headers open-vm-tools xf86-video-vmware # Maybe gtkmm3, if needed.
    systemctl enable vmtoolsd
  fi

  # Install some software. 
  pacman -S --needed --noconfirm firefox firefox-i18n-de vim tmux man

  # Install some software and append some options to the corresponding config file.
  pacman -S --needed --noconfirm tilix
  cat >> /home/$USERNAME/.bashrc << 'EOT' 
if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
        source /etc/profile.d/vte.sh
fi
EOT

  sudo -u $USERNAME paru -S --needed --noconfirm powerline powerline-fonts-git
  cat >> /home/$USERNAME/.bashrc << 'EOT'
powerline-daemon -q
POWERLINE_BASH_CONTINUATION=1
POWERLINE_BASH_SELECT=1
. /usr/share/powerline/bindings/bash/powerline.sh
EOT

  # Append some options to config files.
  cat >> /home/$USERNAME/.vimrc << 'EOT'
let g:powerline_pycmd="py3"
set rtp+=/usr/lib/python3.*/site-packages/powerline/bindings/vim
set laststatus=2
syntax enable
EOT

  cat >> /home/$USERNAME/.tmux.conf << 'EOT'
set -g default-terminal "screen-256color"
source /usr/lib/python3.*/site-packages/powerline/bindings/tmux/powerline.conf
EOT

  # Install and set an icon theme for Gnome.
  sudo -u $USERNAME paru -S --needed --noconfirm paper-icon-theme-git
  sudo -u $USERNAME dbus-launch gsettings set org.gnome.desktop.interface icon-theme 'Paper'

  # This is an example of how to install packages by custom groups. Adapt as you like.
  # The list below is an example for a pentest machine.
  #declare -A PACKAGES
  #PACKAGES[TOOLS]="dnsutils"
  #PACKAGES[RECON]="nikto sslscan wireshark-qt exploitdb"
  #PACKAGES[ENUM]="enum4linux sqlmap gobuster wfuzz wpscan"
  #PACKAGES[SCANNING]="nmap masscan"
  #PACKAGES[SPOOFING]="responder"
  #PACKAGES[EXPLOITATION]="metasploit"

  #for package in ${PACKAGES[@]}; do
  #  sudo -u $USERNAME paru -S --needed --noconfirm $package \
  #    || echo "$package" >> /home/$USERNAME/packages-with-errors.txt
  #done
  
  # Reconfigure sudo, so that a password is need to elevate privileges.
  sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/# //' /etc/sudoers # Uncomment line with sed
  sed -i '/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^/# /' /etc/sudoers # Comment line with sed
  echo "Finished archroot." 
}

# Export the function so that it is visible by bash inside arch-chroot.
export -f archroot
arch-chroot /mnt /bin/bash -c "archroot" || echo "arch-chroot returned: $?"

# Lazy unmount.
umount -l /mnt

cat << 'EOT'
******************************************************
* Finished. You can now reboot into your new system. *
******************************************************
EOT
