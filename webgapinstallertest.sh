#!/bin/sh

if [ $(id -u) != 0 ]; then
    echo "$(tput setaf 3)This script must be run as root.$(tput setaf 9)" 
    exit 1
fi

osrelease=$(awk -F= '$1=="ID" { print $2 ;}' /etc/os-release)

if [ $osrelease != '"rocky"' ] && [ $osrelease != '"centos"' ]; then
    echo "$(tput setaf 3)Please install on CentOS 7 or Rocky 8. You are trying to install on $(tput bold)$osrelease.$(tput setaf 9)"

    sleep 2
    exit 1
fi

if [ $osrelease == '"rocky"' ]; then

    echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9) "
    read answer

    if [ $answer != yes ] && [ $answer != y ]  && [ $answer != no ] && [ $answer != n ]; then
        echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
        
        sleep 2

        echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9) "
        read answer
    fi

    if [ $answer == yes ] || [ $answer == y ]; then

        #upgrade operating system
        yum makecache
        yum -y upgrade

        #install required packages
        yum -y install yum-utils wget git epel-release setools setroubleshoot

        #download nginx repo for stable version
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1ADencnD7rNB0RqT2bB1iFiMVE5fupIOH' -O /etc/yum.repos.d/nginx.repo

        #add docker and nginx repo
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        #install docker-ce and nginx
        yum -y install docker-ce nginx

        #change boolean operators for nginx to allow memory execution, network connection establishment
        setsebool -P httpd_execmem 1
        setsebool -P httpd_can_network_connect 1
        setsebool -P httpd_graceful_shutdown 1
        setsebool -P httpd_can_network_relay 1

        #enable nginx
        systemctl enable nginx

        #download nginx conf template
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1Jw_CcvIqatMn3WVkUI2uMTe3g7WLb58v' -O /etc/nginx/conf.d/default.conf

        #download docker compose
        curl -L "https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

        #make docker-compose executable and enable
        chmod +x /usr/local/bin/docker-compose && ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

        #start docker-ce
        systemctl enable --now docker.service

        #create user docker and add to group docker
        useradd -g docker docker

        #install snapd
        yum install -y snapd

        #enable and start snapd
        systemctl enable --now snapd.socket

        #enable snap classic functionality
        ln -s /var/lib/snapd/snap /snap

        #disable firewalld zone drifiting
        sed -i 's/AllowZoneDrifting=yes/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf

        #ask for public IP
        echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9) "
        read ip

        #GCP sets the trusted zone active which accepts all packets, no rules needed
        echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9) "
        read fw

        if [ $fw != yes ] && [ $fw != y ]  && [ $fw != no ] && [ $fw != n ]; then
        echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"

        sleep 2

        echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9) "
        read fw
        fi
        
        if [ $fw == no ] || [ $fw == n ]; then
        firewall-cmd --permanent --zone=public --add-service=https; firewall-cmd --permanent --zone=public --add-service=http; firewall-cmd --permanent --zone=public --add-port=8001/tcp; firewall-cmd --permanent --zone=public --add-port=3478/tcp; firewall-cmd --permanent --zone=public --add-port=3478/udp; firewall-cmd --permanent --zone=public --add-rich-rule="rule family=ipv4 source address="$ip" accept"; firewall-cmd --permanent --zone=public --remove-service=cockpit; firewall-cmd --reload
        fi

        #restart snapd service for proper seeding before installation of certbot
        systemctl restart snapd.seeded.service

        #install snap core
        snap install core

        #install and enable certbot
        snap install --classic certbot 
        ln -s /snap/bin/certbot /usr/bin/certbot

        #add auto renewal for certbot to crontab
        SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null

        #download webmirror package
        wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg' -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg" -O /opt/webgap-deployment-20210921.tgz && rm -rf /tmp/cookies.txt

        #untar safeweb package
        tar -xzvf /opt/webgap-deployment-20210921.tgz -C /opt

        #make installer executable
        chmod +x /opt/deployment/install.sh

        #change safweb listening port to 8880 from 80 and 8443 from 443
        sed -i '49 s/443:8443/8443:8443/' /opt/deployment/app.yml
        sed -i '50 s/80:8080/8880:8080/' /opt/deployment/app.yml 

        #install safeweb
        cd /opt/deployment; sh install.sh install

        #install turnserver container
        docker run -d -e EXTERNAL_IP=$ip --name=turnserver --restart=always --net=host -p 3478:3478 -p 3478:3478/udp jyangnet/turnserver

        #capture user input for the domain and subdomain to be used for front-end and administration respectively
        echo "$(tput setaf 3)Which domain name would you like to use to access the front-end?$(tput setaf 9) "
        read domain
        echo "$(tput setaf 3)Which sudomain would you like to use to access the administration panel?$(tput setaf 9) "
        read subdomain

        #replace & with variable values for the domain and subdomain in the nginx conf files
        sed -i "s/&/$domain/" /etc/nginx/conf.d/default.conf
        sed -i "s/@/$subdomain/" /etc/nginx/conf.d/default.conf

        #turn server tokens off
        sed -i '26 i\   \ server_tokens off;' /etc/nginx/nginx.conf

        #run certbot twice - once for the front-end domain and once for the administration domain
        echo "$(tput setaf 3)Certbot is going to run for the front-end domain. Select number 1 only.$(tput setaf 9)"
        sleep 3s
        certbot certonly --nginx --preferred-challenges http
        echo "$(tput setaf 3)Certbot is going to run for the administration subdomain. Select number 2 only.$(tput setaf 9)"
        sleep 3s
        certbot certonly --nginx --preferred-challenges http

        #uncomment domain nginx conf lines
        sed -i '2 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '3 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '47 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '48 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '51 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '52 s/#//' /etc/nginx/conf.d/default.conf

        #uncomment subdomain nginx conf lines
        sed -i '88 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '89 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '92 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '93 s/#//' /etc/nginx/conf.d/default.conf

        #optimizations for nginx
        sed -i 's/#tcp_nopush     on;/tcp_nopush      on;/' /etc/nginx/nginx.conf
        sed -i '26 i \   \ tcp_nodelay      on;' /etc/nginx/nginx.conf
        sed -i '27 i \   \ types_hash_max_size 4096;' /etc/nginx/nginx.conf

        #create 4096 bit diffie-hellman key to replace the 2048 bit key
        openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 4096

        #add server IP and domain name to safewab.conf
        sed -i "2 s/SERVER_ADDRESS=66.160.146.247/SERVER_ADDRESS=$domain/" /opt/deployment/safeweb.conf
    

        #bring docker down to save new images
        #cd /opt/deployment; docker-compose -f app.yml down

        #import containers to fix video issue
        #wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1E22jRhTuPX6nufDqy-U0Wn3pnwRjlUAp' -O /opt/deployment/images/safeweb-client.tar

        #start docker w/containers
        #cd /opt/deployment; docker-compose -f app.yml up -d

        #restart server
        echo "$(tput setaf 3)The server is going to restart in 10 seconds.$(tput setaf 9)"
        sleep 10s
        reboot

    else

        #upgrade operating system
        yum makecache
        yum -y upgrade

        #install required packages
        yum -y install yum-utils wget git epel-release setools setroubleshoot

        #download nginx repo for stable version
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1ADencnD7rNB0RqT2bB1iFiMVE5fupIOH' -O /etc/yum.repos.d/nginx.repo

        #add docker and nginx repo
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        #install docker-ce and nginx
        yum -y install docker-ce nginx

        #change boolean operators for nginx to allow memory execution, network connection establishment
        setsebool -P httpd_execmem 1
        setsebool -P httpd_can_network_connect 1
        setsebool -P httpd_graceful_shutdown 1
        setsebool -P httpd_can_network_relay 1

        #enable nginx
        systemctl enable nginx

        #download nginx conf template
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1Jw_CcvIqatMn3WVkUI2uMTe3g7WLb58v' -O /etc/nginx/conf.d/default.conf

        #download docker compose
        curl -L "https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

        #make docker-compose executable and enable
        chmod +x /usr/local/bin/docker-compose && ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

        #start docker-ce
        systemctl enable --now docker.service

        #create user docker and add to group docker
        useradd -g docker docker

        #install snapd
        yum install -y snapd

        #enable and start snapd
        systemctl enable --now snapd.socket

        #enable snap classic functionality
        ln -s /var/lib/snapd/snap /snap

        #disable firewalld zone drifiting
        sed -i 's/AllowZoneDrifting=yes/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf

        #ask for public IP to create firewalld rich rules and close database port
        echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9) "
        read ip
        firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" port port="3306" protocol="tcp" drop'; firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="'$ip'" accept'; firewall-cmd --permanent --zone=public --add-service https; firewall-cmd --permanent --zone=public --add-service http; firewall-cmd --permanent --zone=public --add-port=8001/tcp; firewall-cmd --permanent --zone=public --add-port=3478/tcp; firewall-cmd --permanent --zone=public --add-port=3478/udp; firewall-cmd --permanent --zone=public --remove-service=cockpit; firewall-cmd --reload
    
        #restart snapd service for proper seeding before installation of certbot
        systemctl restart snapd.seeded.service

        #install snap core
        snap install core

        #install and enable certbot
        snap install --classic certbot 
        ln -s /snap/bin/certbot /usr/bin/certbot

        #download webmirror package
        wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg' -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg" -O /opt/webgap-deployment-20210921.tgz && rm -rf /tmp/cookies.txt

        #untar safeweb package
        tar -xzvf /opt/webgap-deployment-20210921.tgz -C /opt

        #make installer executable
        chmod +x /opt/deployment/install.sh

        #change safweb listening port to 8880 from 80 and 8443 from 443
        sed -i '49 s/443:8443/8443:8443/' /opt/deployment/app.yml
        sed -i '50 s/80:8080/8880:8080/' /opt/deployment/app.yml 

        #install safeweb
        cd /opt/deployment; sh install.sh install

        #install turnserver container
        docker run -d  EXTERNAL_IP=$ip --name=turnserver --restart=always --net=host -p 3478:3478 -p 3478:3478/udp jyangnet/turnserver

        #capture user input for the domain and subdomain to be used for front-end and administration respectively
        echo "$(tput setaf 3)Which domain name would you like to use to access the front-end?$(tput setaf 9) "
        read domain
        echo "$(tput setaf 3)Which sudomain would you like to use to access the administration panel?$(tput setaf 9) "
        read subdomain

        #replace & with variable values for the domain and subdomain in the nginx conf files
        sed -i "s/&/$domain/" /etc/nginx/conf.d/default.conf
        sed -i "s/@/$subdomain/" /etc/nginx/conf.d/default.conf

        #turn server tokens off
        sed -i '26 i\   \ server_tokens off;' /etc/nginx/nginx.conf

        #run certbot twice - once for the front-end domain and once for the administration domain
        echo "$(tput setaf 3)Certbot is going to run for the front-end domain. Select number 1 only.$(tput setaf 9)"
        sleep 3s
        certbot certonly --nginx --preferred-challenges http
        echo "$(tput setaf 3)Certbot is going to run for the administration subdomain. Select number 2 only.$(tput setaf 9)"
        sleep 3s
        certbot certonly --nginx --preferred-challenges http

        #uncomment domain nginx conf lines
        sed -i '2 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '3 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '47 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '48 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '51 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '52 s/#//' /etc/nginx/conf.d/default.conf

        #uncomment subdomain nginx conf lines
        sed -i '88 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '89 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '92 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '93 s/#//' /etc/nginx/conf.d/default.conf

        #optimizations for nginx
        sed -i 's/#tcp_nopush     on;/tcp_nopush      on;/' /etc/nginx/nginx.conf
        sed -i '26 i \   \ tcp_nodelay      on;' /etc/nginx/nginx.conf
        sed -i '27 i \   \ types_hash_max_size 4096;' /etc/nginx/nginx.conf

        #create 4096 bit diffie-hellman key to replace the 2048 bit key
        openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 4096

        #add server IP and domain name to safewab.conf
        sed -i "2 s/SERVER_ADDRESS=66.160.146.247/SERVER_ADDRESS=$domain/" /opt/deployment/safeweb.conf
        sed -i "5 s/SERVER_IP=66.160.146.247/SERVER_IP=$ip/" /opt/deployment/safeweb.conf

        #bring docker down to save new images
        #cd /opt/deployment; docker-compose -f app.yml down

        #import containers to fix video issue
        #wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1E22jRhTuPX6nufDqy-U0Wn3pnwRjlUAp' -O /opt/deployment/images/safeweb-client.tar

        #start docker w/containers
        #cd /opt/deployment; docker-compose -f app.yml up -d

        #restart server
        echo "$(tput setaf 3)The server is going to restart in 10 seconds.$(tput setaf 9)"
        sleep 10s
        reboot
    fi

else

    echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9) "
    read answer
    
    if [ $answer != yes ] && [ $answer != y ]  && [ $answer != no ] && [ $answer != n ]; then
        echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"
    
        sleep 2

        echo "$(tput setaf 3)Are you deploying in a virtual private cloud or DMZ (yes/no)?$(tput setaf 9) "
        read answer
    fi  

    if [ $answer == yes ] || [  $answer == y ]; then

        #upgrade operating system
        yum makecache fast
        yum -y upgrade

        #install required packages
        yum -y install yum-utils wget epel-release setools setroubleshoot

        #download nginx repo for stable version
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1ADencnD7rNB0RqT2bB1iFiMVE5fupIOH' -O /etc/yum.repos.d/nginx.repo

        #add docker and nginx repo
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        #install docker-ce and nginx
        yum -y install docker-ce nginx

        #change boolean operators for nginx to allow memory execution, network connection establishment
        setsebool -P httpd_execmem 1
        setsebool -P httpd_can_network_connect 1
        setsebool -P httpd_graceful_shutdown 1
        setsebool -P httpd_can_network_relay 1

        #enable nginx
        systemctl enable nginx

        #download nginx conf template
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1Jw_CcvIqatMn3WVkUI2uMTe3g7WLb58v' -O /etc/nginx/conf.d/default.conf

        #download docker compose
        curl -L "https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

        #make docker-compose executable and enable
        chmod +x /usr/local/bin/docker-compose && ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

        #start docker-ce
        systemctl enable --now docker.service

        #create user docker and add to group docker
        useradd -g docker docker

        #install snapd
        yum install -y snapd

        #enable and start snapd
        systemctl enable --now snapd.socket

        #enable snap classic functionality
        ln -s /var/lib/snapd/snap /snap

        #disable firewalld zone drifiting
        sed -i 's/AllowZoneDrifting=yes/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf

        #ask for public IP
        echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9) "
        read ip

        #GCP sets the trusted zone active which accepts all packets, no rules needed
        echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9) "
        read fw

        if [ $fw != yes ] && [ $fw != y ]  && [ $fw != no ] && [ $fw != n ]; then
        echo "$(tput setaf 3)Please answer with yes or no.$(tput setaf 9)"

        sleep 2

        echo "$(tput setaf 3)Is your firewall active zone the Trusted zone (yes/no)?$(tput setaf 9) "
        read fw
        fi
        
        if [ $fw == no ] || [ $fw == n ]; then
        firewall-cmd --permanent --zone=public --add-service=https; firewall-cmd --permanent --zone=public --add-service=http; firewall-cmd --permanent --zone=public --add-port=8001/tcp; firewall-cmd --permanent --zone=public --add-port=3478/tcp; firewall-cmd --permanent --zone=public --add-port=3478/udp; firewall-cmd --permanent --zone=public --add-rich-rule="rule family=ipv4 source address="$ip" accept"; firewall-cmd --reload
        fi

        #restart snapd service for proper seeding before installation of certbot
        systemctl restart snapd.seeded.service

        #install snap core
        snap install core

        #install and enable certbot
        snap install --classic certbot 
        ln -s /snap/bin/certbot /usr/bin/certbot

        #add auto renewal for certbot to crontab
        SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null

        #download webmirror package
        wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg' -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg" -O /opt/webgap-deployment-20210921.tgz && rm -rf /tmp/cookies.txt

        #untar safeweb package
        tar -xzvf /opt/webgap-deployment-20210921.tgz -C /opt

        #make installer executable
        chmod +x /opt/deployment/install.sh

        #change safweb listening port to 8880 from 80 and 8443 from 443
        sed -i '49 s/443:8443/8443:8443/' /opt/deployment/app.yml
        sed -i '50 s/80:8080/8880:8080/' /opt/deployment/app.yml 

        #install safeweb
        cd /opt/deployment; sh install.sh install

        #install turnserver container
        docker run -d -e EXTERNAL_IP=$ip --name=turnserver --restart=always --net=host -p 3478:3478 -p 3478:3478/udp jyangnet/turnserver

        #capture user input for the domain and subdomain to be used for front-end and administration respectively
        echo "$(tput setaf 3)Which domain name would you like to use to access the front-end?$(tput setaf 9) "
        read domain
        echo "$(tput setaf 3)Which sudomain would you like to use to access the administration panel?$(tput setaf 9) "
        read subdomain

        #replace & with variable values for the domain and subdomain in the nginx conf files
        sed -i "s/&/$domain/" /etc/nginx/conf.d/default.conf
        sed -i "s/@/$subdomain/" /etc/nginx/conf.d/default.conf

        #turn server tokens off
        sed -i '26 i\   \ server_tokens off;' /etc/nginx/nginx.conf

        #run certbot twice - once for the front-end domain and once for the administration domain
        echo "$(tput setaf 3)Certbot is going to run for the front-end domain.$(tput setaf 9)"
        sleep 3s
        certbot certonly --nginx --preferred-challenges http
        echo "$(tput setaf 3)Certbot is going to run for the administration subdomain.$(tput setaf 9)"
        sleep 3s
        certbot certonly --nginx --preferred-challenges http

        #uncomment domain nginx conf lines
        sed -i '2 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '3 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '47 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '48 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '51 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '52 s/#//' /etc/nginx/conf.d/default.conf

        #uncomment subdomain nginx conf lines
        sed -i '88 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '89 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '92 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '93 s/#//' /etc/nginx/conf.d/default.conf

        #optimizations for nginx
        sed -i 's/#tcp_nopush     on;/tcp_nopush      on;/' /etc/nginx/nginx.conf
        sed -i '26 i \   \ tcp_nodelay      on;' /etc/nginx/nginx.conf
        sed -i '27 i \   \ types_hash_max_size 4096;' /etc/nginx/nginx.conf

        #create 4096 bit diffie-hellman key to replace the 2048 bit key
        openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 4096

        #add server IP and domain name to safewab.conf
        sed -i "2 s/SERVER_ADDRESS=66.160.146.247/SERVER_ADDRESS=$domain/" /opt/deployment/safeweb.conf
        sed -i "5 s/SERVER_IP=66.160.146.247/SERVER_IP=$ip/" /opt/deployment/safeweb.conf

        #bring docker down to save new images
        cd /opt/deployment; docker-compose -f app.yml down

        #import containers to fix video issue
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1E22jRhTuPX6nufDqy-U0Wn3pnwRjlUAp' -O /opt/deployment/images/safeweb-client.tar

        #start docker w/containers
        cd /opt/deployment; docker-compose -f app.yml up -d

        #restart server
        echo "$(tput setaf 3)The server is going to restart in 10 seconds.$(tput setaf 9)"
        sleep 10s
        reboot

    else

        #upgrade operating system
        yum makecache fast
        yum -y upgrade

        #install required packages
        yum -y install yum-utils wget epel-release setools setroubleshoot

        #download nginx repo for stable version
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1ADencnD7rNB0RqT2bB1iFiMVE5fupIOH' -O /etc/yum.repos.d/nginx.repo

        #add docker and nginx repo
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        #install docker-ce and nginx
        yum -y install docker-ce nginx

        #change boolean operators for nginx to allow memory execution, network connection establishment
        setsebool -P httpd_execmem 1
        setsebool -P httpd_can_network_connect 1
        setsebool -P httpd_graceful_shutdown 1
        setsebool -P httpd_can_network_relay 1

        #enable nginx
        systemctl enable nginx

        #download nginx conf template
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1Jw_CcvIqatMn3WVkUI2uMTe3g7WLb58v' -O /etc/nginx/conf.d/default.conf

        #download docker compose
        curl -L "https://github.com/docker/compose/releases/download/1.29.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

        #make docker-compose executable and enable
        chmod +x /usr/local/bin/docker-compose && ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

        #start docker-ce
        systemctl enable --now docker.service

        #create user docker and add to group docker
        useradd -g docker docker

        #install snapd
        yum install -y snapd

        #enable and start snapd
        systemctl enable --now snapd.socket

        #enable snap classic functionality
        ln -s /var/lib/snapd/snap /snap

        #disable firewalld zone drifiting
        sed -i 's/AllowZoneDrifting=yes/AllowZoneDrifting=no/' /etc/firewalld/firewalld.conf

        #ask for public IP to create firewalld rich rules and close database port
        echo "$(tput setaf 3)What is the IP address assigned to the host network interface?$(tput setaf 9) "
        read ip
        firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" port port="3306" protocol="tcp" drop'; firewall-cmd --permanent --zone=public --add-service https; firewall-cmd --permanent --zone=public --add-service http; firewall-cmd --permanent --zone=public --add-port=8001/tcp; firewall-cmd --permanent --zone=public --add-port=3478/tcp; firewall-cmd --permanent --zone=public --add-port=3478/udp; firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="'$ip'" accept'; firewall-cmd --reload 

        #restart snapd service for proper seeding before installation of certbot
        systemctl restart snapd.seeded.service

        #install snap core
        snap install core

        #install and enable certbot
        snap install --classic certbot 
        ln -s /snap/bin/certbot /usr/bin/certbot

        #add auto renewal for certbot to crontab
        SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null

        #download webmirror package
        wget --load-cookies /tmp/cookies.txt "https://docs.google.com/uc?export=download&confirm=$(wget --quiet --save-cookies /tmp/cookies.txt --keep-session-cookies --no-check-certificate 'https://docs.google.com/uc?export=download&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg' -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p')&id=1rANxv6TJwyZQpxwUvzCz-oqCTdDdugXg" -O /opt/webgap-deployment-20210921.tgz && rm -rf /tmp/cookies.txt

        #untar safeweb package
        tar -xzvf /opt/webgap-deployment-20210921.tgz -C /opt

        #make installer executable
        chmod +x /opt/deployment/install.sh

        #change safweb listening port to 8880 from 80 and 8443 from 443
        sed -i '49 s/443:8443/8443:8443/' /opt/deployment/app.yml
        sed -i '50 s/80:8080/8880:8080/' /opt/deployment/app.yml 

        #install safeweb
        cd /opt/deployment; sh install.sh install

        #install turnserver container
        docker run -d -e EXTERNAL_IP=$ip --name=turnserver --restart=always --net=host -p 3478:3478 -p 3478:3478/udp jyangnet/turnserver

        #capture user input for the domain and subdomain to be used for front-end and administration respectively
        echo "$(tput setaf 3)Which domain name would you like to use to access the front-end?$(tput setaf 9) "
        read domain
        echo "$(tput setaf 3)Which sudomain would you like to use to access the administration panel?$(tput setaf 9) "
        read subdomain

        #replace & with variable values for the domain and subdomain in the nginx conf files
        sed -i "s/&/$domain/" /etc/nginx/conf.d/default.conf
        sed -i "s/@/$subdomain/" /etc/nginx/conf.d/default.conf

        #turn server tokens off
        sed -i '26 i\   \ server_tokens off;' /etc/nginx/nginx.conf

        #run certbot twice - once for the front-end domain and once for the administration domain
        echo "$(tput setaf 3)Certbot is going to run for the front-end domain.$(tput setaf 9)"
        sleep 3s
        certbot certonly --nginx --preferred-challenges http
        echo "$(tput setaf 3)Certbot is going to run for the administration subdomain.$(tput setaf 9)"
        sleep 3s
        certbot certonly --nginx --preferred-challenges http

        #uncomment domain nginx conf lines
        sed -i '2 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '3 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '47 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '48 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '51 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '52 s/#//' /etc/nginx/conf.d/default.conf

        #uncomment subdomain nginx conf lines
        sed -i '88 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '89 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '92 s/#//' /etc/nginx/conf.d/default.conf
        sed -i '93 s/#//' /etc/nginx/conf.d/default.conf

        #optimizations for nginx
        sed -i 's/#tcp_nopush     on;/tcp_nopush      on;/' /etc/nginx/nginx.conf
        sed -i '26 i \   \ tcp_nodelay      on;' /etc/nginx/nginx.conf
        sed -i '27 i \   \ types_hash_max_size 4096;' /etc/nginx/nginx.conf

        #create 4096 bit diffie-hellman key to replace the 2048 bit key
        openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 4096

        #add server IP and domain name to safewab.conf
        sed -i "2 s/SERVER_ADDRESS=66.160.146.247/SERVER_ADDRESS=$domain/" /opt/deployment/safeweb.conf
        sed -i "5 s/SERVER_IP=66.160.146.247/SERVER_IP=$ip/" /opt/deployment/safeweb.conf

        #bring docker down to save new images
        cd /opt/deployment; docker-compose -f app.yml down

        #import containers to fix video issue
        wget --no-check-certificate 'https://docs.google.com/uc?export=download&id=1E22jRhTuPX6nufDqy-U0Wn3pnwRjlUAp' -O /opt/deployment/images/safeweb-client.tar

        #start docker w/containers
        cd /opt/deployment; docker-compose -f app.yml up -d

        #restart server
        echo "$(tput setaf 3)The server is going to restart in 10 seconds.$(tput setaf 9)"
        sleep 10s
        reboot
    fi
fi