#!/bin/bash
# Wrote by Se1ah
ssh_user=$1
remote_host=$2
smtp_server=$3
email_address=$4
smtp_port=$5
# Must used with single quotation because we have non alphabetical characters in password string
password=$6
# reads remote hostname by given IP address
remote_hostname=$(ssh "$ssh_user"@"$remote_host" 'hostname')
mysql_password=$7
if [ $HOSTNAME == "Put target hostname in here [the host you ssh to]" ]; then
    dpkg -s mysql-server > /dev/null
    if [ $? -eq 0 ]; then 
            echo "Pachage mysql-server is already installed"
    else
            export DEBIAN_FRONTEND="noninteractive"
            sudo debconf-set-selections <<< "mysql-server mysql-server/root_password $mysql_password $1"
            sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again $mysql_password $1"
            sudo apt install -y mysql-server
            sudo service mysql start
    fi

    # MySQL Server Process ID
    mysql_pid=$(sudo service mysql status | grep "Main PID" | cut -d":" -f 2 | cut -d" " -f 2)
    mysql_mem_usage=$(sudo service mysql status | grep "Memory" | cut -d":" -f 2 | cut -d" " -f 2)
    echo "MySQL Server PID is $mysql_pid and it took $mysql_mem_usage of RAM"
    
    # Installing postfix
    dpkg -s postfix > /dev/null
    if [ $? -eq 0 ]; then 
        echo "Package postfix is already installed"
    else
        debconf-set-selections <<< "postfix postfix/mailname string your.hostname.com" 
        debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
        sudo apt install -y postfix mailutils
    fi
    #Inside single quotes everything is preserved literally, without exception.
    #That means you have to close the quotes, insert something, and then re-enter again.
    sudo sh -c 'echo ['"$smtp_server"']:'"$smtp_port"' '"$email_address"':'"$password"' > /etc/postfix/sasl/sasl_passwd'
    sudo sh -c 'chmod 0600 /etc/postfix/sasl/sasl_passwd'
    # The following line will create the file /etc/postfix/sasl/sasl_passwd.db
    sudo postmap /etc/postfix/sasl/sasl_passwd
    # postconf updates /etc/postfix/main.cf file
    sudo postconf -e relayhost=["$smtp_server"]:"$smtp_port"
    sudo postconf -e smtp_sasl_auth_enable=yes
    sudo postconf -e smtp_sasl_security_options=noanonymous
    sudo postconf -e smtp_sasl_password_maps=hash:/etc/postfix/sasl/sasl_passwd
    sudo postconf -e smtp_tls_security_level=encrypt
    sudo postconf -e smtp_tls_security_level=verify
    sudo postconf -e smtp_tls_CAfile=/etc/ssl/certs/ca-bundle.crt
    sudo systemctl enable postfix
    sudo systemctl restart postfix
    # Making our custom service
    sudo touch /etc/systemd/system/email-mysql-logs.service
    sudo sh -c 'printf "[Unit]\nDescription=Example systemd service.\n\n[Service]\nType=simple\nExecStart=/bin/bash /tmp/my_sendmail.sh\n\n[Install]\nWantedBy=multi-user.target\n" > /etc/systemd/system/email-mysql-logs.service'
     sudo chmod 644 /etc/systemd/system/email-mysql-logs.service
    # Creating send mail executable
    printf '#!/bin/bash\nwget -q --tries=10 --timeout=20 --spider http://google.com\nif [[ $? -ne 0 ]]; then\n\techo "Please check your internet connectivity"\n\texit\nelse\n\tsudo journalctl -n 20 -u mysql.service | nl -b a -s "." > /tmp/mysql.log\n\tmail --debug-level=all -s "MySQL Log $(date)" '"$email_address"' < /tmp/mysql.log\nfi' > /tmp/my_sendmail.sh
    sudo chmod +x /tmp/my_sendmail.sh
    sudo systemctl start email-mysql-logs.service
    sudo systemctl enable email-mysql-logs.service

    # we create a systemd timer with the same name as the previous service to run it every 12 hours
    printf '#!/bin/bash\nsudo journalctl -n 20 -u mysql.service | nl -b a -s "." > /tmp/mysql.log\nmail --debug-level=all -s "MySQL Log $(date)" '"$email_address"' < /tmp/mysql.log' > /tmp/my_sendmail.sh
    sudo systemctl enable email-mysql-logs.timer
    sudo systemctl start email-mysql-logs.timer
fi


if [ "$HOSTNAME" == "$remote_host" ]; then
        exit
fi
scp $PWD/remote "$ssh_user"@"$remote_host":/tmp
parent=$(ps $PPID | tail -n 1 | awk "{print \$5}")
if [ "$parent" == "-bash" ]; then
ssh -t "$ssh_user"@"$remote_host" 'chmod +x /tmp/config.sh; sh -c /tmp/config.sh'
fi
