Vagrant.configure(2) do |config|
    config.vm.provider :virtualbox do |vb|
        vb.memory = 1024
        vb.cpus = 2
    end

    config.vm.box = "ubuntu/trusty64"

    config.vm.provider :virtualbox do |vb|
        vb.name = "expresspg-ubuntu-14.04"
    end

    # Provision the VM
    config.vm.provision "shell", inline: <<-SHELL
        # Install db packages
        echo 'deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main 9.5' >> /etc/apt/sources.list.d/pgdg.list
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
        apt-get update

        # Install db
        apt-get install -y postgresql-9.4

        # Allow connections from the host machine (also disables all security for local connections - be careful!)
        echo "listen_addresses = '*'" >> /etc/postgresql/9.4/main/postgresql.conf
        echo "host all all 10.0.0.0/8 trust" >> /etc/postgresql/9.4/main/pg_hba.conf
        /etc/init.d/postgresql restart

        # Create vagrant user to do builds
        sudo -u postgres psql -c "create user vagrant with password 'vagrant' superuser" postgres
    SHELL

  # Share the expresspg folder
  config.vm.synced_folder ".", "/expresspg"

  # Share PostgreSQL with the host
  config.vm.network "forwarded_port", guest: 5432, host: 6543
end
