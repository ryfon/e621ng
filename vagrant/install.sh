#!/usr/bin/env bash

APP_DIR=/home/danbooru/danbooru
CHRUBY_PATH=/etc/profile.d/chruby.sh

echo "debconf debconf/frontend select noninteractive" | sudo debconf-set-selections
sed -i -e 's/\(AcceptEnv LANG LC_\*\)/#\1/' /etc/ssh/sshd_config
service sshd restart

package_installed() {
	if dpkg-query -f '${binary:Package}\n' -W | grep "$1" &>/dev/null; then
		return 0;
	else
		return 1;
	fi
}

add_key() {
	wget -qO - "$1" | sudo apt-key add - &>/dev/null
}

install_packages() {
	sudo apt-get install -y $@
}

script_log() {
	echo "[install.sh] >>> $@"
}

if ! grep danbooru /etc/passwd >/dev/null; then
    script_log "Creating danbooru system user..."
    useradd -m -s /bin/bash -U danbooru
    cp -pr /home/vagrant/.ssh /home/danbooru/
    chown -R danbooru:danbooru /home/danbooru
    echo "%danbooru ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/danbooru
    ln -s /vagrant /home/danbooru/danbooru
    usermod -aG vagrant,www-data danbooru
fi

if ! package_installed postgresql-9.6; then
    add_key https://www.postgresql.org/media/keys/ACCC4CF8.asc
    echo "deb http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    script_log "PostgreSQL repository added"
fi

if ! package_installed nginx; then
    add_key http://nginx.org/keys/nginx_signing.key
	  echo "deb http://nginx.org/packages/debian/ stretch nginx" > /etc/apt/sources.list.d/nginx.list
    script_log "nginx repository added"
fi

if ! package_installed nodejs; then
    install_packages curl
    curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash - >/dev/null 2>&1
    script_log "Node.js repository added"
fi

if ! package_installed yarn; then
    add_key https://dl.yarnpkg.com/debian/pubkey.gpg
    echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list
    script_log "yarn repository added"
fi

echo "deb http://http.debian.net/debian stretch-backports main" | sudo tee /etc/apt/sources.list.d/stretch-backports.list
sudo apt-get update

if ! package_installed nginx; then
    script_log "Installing nginx..."
    install_packages nginx
fi

if ! package_installed postgresql-9.6; then
    script_log "Installing PostgreSQL..."
    install_packages postgresql-11
    sed -i -e 's/md5/trust/' /etc/postgresql/11/main/pg_hba.conf
    service postgresql restart
fi

if ! package_installed yarn; then
    script_log "Installing yarn..."
    install_packages yarn
fi

if ! install_packages \
      build-essential automake libxml2-dev libxslt-dev ncurses-dev \
      libreadline-dev flex bison ragel memcached libmemcached-dev git curl \
      libcurl4-openssl-dev sendmail-bin sendmail nginx ssh coreutils ffmpeg \
      mkvtoolnix cmake ffmpeg gifsicle git inkscape libcurl4-openssl-dev \
      libicu-dev libjpeg-progs libopencv-dev libpq-dev libreadline-dev \
      libxml2-dev nodejs optipng redis-server libvips-tools; then
	>&2 script_log "Installation of other dependencies failed, please see the errors above and re-run \`vagrant provision\`"
	exit 1
fi

script_log "Creating danbooru Postgres user..."
sudo -u postgres createuser -s danbooru

if ! type ruby-install >/dev/null 2>&1; then
    script_log "Installing ruby-install..."
    cd /usr/local/src
    wget -qO ruby-install-0.7.0.tar.gz https://github.com/postmodern/ruby-install/archive/v0.7.0.tar.gz
    tar -xzvf ruby-install-0.7.0.tar.gz >/dev/null
    cd ruby-install-0.7.0/
    sudo make install >/dev/null
    rm /usr/local/src/ruby-install-0.7.0.tar.gz

    echo "export RAILS_ENV=development" > /etc/profile.d/rails_env.sh
fi

if [ -f "$CHRUBY_PATH" ]; then
    source $CHRUBY_PATH
fi

if ! type chruby >/dev/null 2>&1; then
    script_log "Installing chruby..."
    cd /usr/local/src
    wget -qO chruby-0.3.9.tar.gz https://github.com/postmodern/chruby/archive/v0.3.9.tar.gz
    tar -xzvf chruby-0.3.9.tar.gz >/dev/null
    cd chruby-0.3.9/
    sudo make install >/dev/null
    sudo ./scripts/setup.sh >/dev/null
    rm /usr/local/src/chruby-0.3.9.tar.gz

    echo -e \
"if [ -n \"\$BASH_VERSION\" ] || [ -n \"\$ZSH_VERSION\" ]; then
  source /usr/local/share/chruby/chruby.sh
  source /usr/local/share/chruby/auto.sh
fi" > $CHRUBY_PATH
fi

script_log "Linking libvips library..."
ln -s /usr/lib/x86_64-linux-gnu/libvips.so.42 /usr/lib/libvips.so

SETUP_SCRIPT=/vagrant/vagrant/ruby-setup.sh
chmod a+x $SETUP_SCRIPT
sudo -u danbooru bash -c "$SETUP_SCRIPT '$APP_DIR' '$CHRUBY_PATH'"


NGINX_CONFIG_PATH=/etc/nginx/conf.d/danbooru.conf
NGINX_DEFAULT_CONFIG_PATH=/etc/nginx/conf.d/default.conf
script_log "Linking nginx config file..."
if [ -f "$NGINX_CONFIG_PATH" ]; then
    rm "$NGINX_CONFIG_PATH"
fi
sudo ln -s $APP_DIR/script/install/nginx.danbooru.conf "$NGINX_CONFIG_PATH"
sed -i -e 's/__hostname__/e621.lc/' "$NGINX_CONFIG_PATH"
if [ -f "$NGINX_DEFAULT_CONFIG_PATH" ]; then
    rm "$NGINX_DEFAULT_CONFIG_PATH"
fi

service nginx restart

script_log "Stopping danbooru systemd service..."
service danbooru stop 2>/dev/null

script_log "Copying systemd unit file..."
cp $APP_DIR/vagrant/danbooru.service /lib/systemd/system/
systemctl daemon-reload
systemctl enable danbooru 2>/dev/null

script_log "Restarting danbooru systemd service..."
service danbooru restart
