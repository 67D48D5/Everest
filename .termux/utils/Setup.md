# Setup

Setup Guide for Termux with Magisk

## On Android

> Ensure to download **Debug** versions from **GitHub**, as the Play Store versions may have limitations.

1. Install [Termux](https://github.com/termux/termux-app/releases) from **GitHub**.
2. Install [Termux:Boot](https://github.com/termux/termux-boot/releases) from **GitHub**.
3. Turn on **ADB** and **USB Debugging** in **Developer Options**.

Open `Termux` and run the following commands:

```bash
# Prevent device sleep
termux-wake-lock
# Termux storage setup
termux-setup-storage

# Update package lists and upgrade installed packages
pkg update && pkg upgrade -y

# Install OpenSSH and set password for SSH access
pkg install -y openssh && passwd && sshd
```

## Continue at PC

Connect to `ssh user@termux_ip_address -p 8022`

### Install essential packages

```bash
# Install `root-repo`
pkg install -y root-repo

# Install additional packages
pkg install -y termux-services tsu zsh git wget curl jq openjdk-21 tmux mariadb htop tree zip unzip neovim vim
```

### Enable Termux services

```bash
# Enable Termux services
bash -c "sv-enable mysqld && sv-enable sshd && sv-enable ssh-agent"
```

### Setup for MariaDB

> Be sure to run `mysqld` at first!

```bash
# Start MariaDB
sv start mysqld

# Secure MariaDB installation
mariadb-secure-installation
```

### Install `Oh-My-Zsh`

```sh
# Install Oh My Zsh non-interactively
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install Powerlevel10k theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k

# Install Zsh Syntax Highlighting plugin
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Install Zsh Auto Suggestions plugin
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# Edit `.zshrc` to set the theme and add the new plugins
sed -i 's/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/' ~/.zshrc
sed -i '/plugins=(git)/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' ~/.zshrc
```

### SSH Key Generation for GitHub

```sh
eval "$(ssh-agent -s)"
ssh-keygen -t ed25519 -C "Everest"
ssh-add ~/.ssh/id_ed25519 && cat ~/.ssh/id_ed25519.pub

git clone git@github.com:67D48D5/Everest.git
```
