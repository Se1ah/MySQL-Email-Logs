#!/bin/bash
# Wrote by Salah
# We check to see if mysql-server is installed 
# This if is tested individually and worked just right.
mysql_password='put your mysql password here'
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

    # Email configuration
    smtp_server="put your smtp server here"
    email_address="put your email here"
    smtp_port="put your smtp port number here"
    # Must used with single quotation because we have non alphabetical characters in password string
    password='put your mail password in here'
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
    sudo postconf -e relayhost=[smtp.gmail.com]:587
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
    printf 'mail --debug-level=all -s "MySQL Log $(date) '"$email_address"' < /tmp/mysql.log' > /tmp/my_sendmail.sh
    sudo chmod +x /tmp/my_sendmail.sh
    sudo systemctl start email-mysql-logs.service
    sudo systemctl enable email-mysql-logs.service

    # we create a systemd timer with the same name as the previous service to run it every 12 hours
    sudo sh -c 'printf "[Unit]\nDescription=run my script\n\n[Timer]\nOnUnitActiveSec=12h\nPersistent=true\n\n[Install]\nWantedBy=timers.target" > /etc/systemd/system/email-mysql-logs.timer'
    sudo systemctl enable email-mysql-logs.timer
    sudo systemctl start email-mysql-logs.timer
fi

ssh_username="put your ssh username here"
ssh_host="put the ip/domain name of your host in here"
# This if condition prevent the parent to invoke this part recursively
if [ $(ps -o comm= $PPID) == "-bash" ]; then
    ssh "$ssh_username"@"$ssh_host" 'bash -s' < my-config.sh
fi
