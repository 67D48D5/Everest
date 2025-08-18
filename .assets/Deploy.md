# Deploy

Let's get started with deploying Everest on Amazon Web Services.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Deployment](#deployment)
  - [EC2](#ec2)
  - [S3](#s3)

## Overview

In this guide, we will cover the deployment of the Everest server on AWS. We will utilize various AWS services, including EC2 for compute resources and S3 for storage.

What we will cover:

- Setting up the EC2 instance for `compute resources`
- Configuring S3 for `static` data storage
- Deploying the Everest Minecraft server

### Prerequisites

Before you begin, ensure you have the following:

- An AWS account
- AWS CLI installed and configured
- Basic knowledge of AWS services

## Architecture

### `One` Architecture

`One` architecture is a monolithic design where all components are tightly integrated and run as a single service. This approach simplifies deployment and scaling but can lead to challenges in managing complexity and resource allocation.

### Sharding Architecture

Sharding architecture involves breaking the database into smaller, more manageable pieces called shards. Each shard is a separate database instance that can be hosted on different servers. This approach improves scalability and performance by distributing the load across multiple instances.

## Deployment

First we need to set up the EC2 instance. Before launching the instance, we need to create a key pair and a security group.

### EC2

> `t4g.small` with `Amazon Linux 2023`

On `t4g.small`, The vCPU and memory configuration is optimized for burstable performance, making it suitable for a variety of workloads.

2 vCPUs and 2 GiB of memory, if you need more memory, consider using a larger instance type. i.e. `t4g.medium` with 2 vCPUs and 4 GiB of memory.

#### cloud-init

The `cloud-init` configuration file is used to customize the EC2 instance at launch. It installs necessary packages, sets the default shell to Zsh, and configures the user's environment.

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - zsh
  - git
  - wget
  - unzip
  - screen
  - tmux
  - tree
  - htop
  - vim
  - jq
  - util-linux-user
  - mariadb1011-server
  - java-21-amazon-corretto-devel

# Set the default user's shell to zsh.
# NOTE: The default user on Amazon Linux is 'ec2-user'
system_info:
  default_user:
    shell: /bin/zsh

runcmd:
  # Reinstall `curl`
  - sudo yum install --allowerasing -y curl
  # Remove Amazon Linux banner
  - sudo touch /etc/motd.d/30-banner
  # Install Oh My Zsh non-interactively for the 'ec2-user'
  # The `"" --unattended` part prevents the script from hanging.
  - su - ec2-user -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
  # Install Powerlevel10k theme
  - su - ec2-user -c "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k"
  # Install Zsh Syntax Highlighting plugin
  - su - ec2-user -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
  # Install Zsh Auto Suggestions plugin
  - su - ec2-user -c "git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
  # Edit `.zshrc` to set the theme and add the new plugins
  - su - ec2-user -c "sed -i 's/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/' ~/.zshrc"
  - su - ec2-user -c "sed -i '/plugins=(git)/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' ~/.zshrc"
```

This pre-configured environment will help streamline the setup process for the Everest server.

It has cosmetic enhancements and useful plugins for a better development experience.

#### Swap and Mount Data Storage

```sh
sudo fallocate -l 6G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
free -h

sudo mkfs -t xfs /dev/xvdbb
sudo mkdir /data
sudo mount /dev/xvdbb /data
sudo blkid /dev/xvdbb
df -h

sudo vim /etc/fstab
# UUID=     /data       xfs    defaults,nofail   0   2
#
# /swapfile none swap sw 0 0

sudo chown ec2-user:ec2-user /data
ln -s /data ~/data
```

#### SSH Key Generation for GitHub

```sh
eval "$(ssh-agent -s)"
ssh-keygen -t ed25519 -C "Everest"
ssh-add ~/.ssh/id_ed25519 && cat ~/.ssh/id_ed25519.pub

git clone git@github.com:67D48D5/Everest.git /data
```

#### MariaDB Setup

```sh
# Start MariaDB and enable it to start on boot
sudo systemctl enable --now mariadb
# Secure the MariaDB installation
sudo mysql_secure_installation

# Import the initial database schema
mariadb -u root -p </data/.assets/Base.sql
```

### S3

```sh
aws s3 cp s3://everest-prod-storage/worlds/ . --recursive
```
