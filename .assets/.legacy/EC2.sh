# Update packages
sudo yum update && sudo yum upgrade -y

# Remove Amazon Linux banner
sudo touch /etc/motd.d/30-banner

sudo yum install -y zsh git curl wget tmux jq java-21-amazon-corretto-devel tree vim util-linux-user mariadb1011-server --allowerasing
sudo systemctl enable --now mariadb

sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

sudo fallocate -l 6G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
free -h

sudo mkfs -t xfs /dev/xvdbb
sudo mkdir /data
sudo mount /dev/xvdbb /data
sudo blkid /dev/xvdbb
sudo vim /etc/fstab
df -h

sudo chown ec2-user:ec2-user /data
ln -s /data ~/data

sudo mysql_secure_installation
mariadb -u root -p </data/.assets/.sql

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

vim ~/.zshrc

eval "$(ssh-agent -s)"
ssh-keygen -t ed25519 -C "Everest"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub

git clone git@github.com:67D48D5/Everest.git
