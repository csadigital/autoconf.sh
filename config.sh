#!/bin/bash

echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

echo "noop" > /sys/block/sda/queue/scheduler

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

/usr/local/lsws/bin/lswsctrl stop
/usr/local/lsws/bin/lswsctrl start

imunify360-agent cleanup all

csf -r

cagefsctl --remount-all
ldconfig

/scripts/restartsrv_httpd
/scripts/restartsrv_cpsrvd
/scripts/restartsrv_mariadb
/scripts/restartsrv_named

echo "[mysqld]
performance-schema = off
innodb_buffer_pool_size = 4G
query_cache_type = 1
query_cache_limit = 2M
query_cache_size = 64M
tmp_table_size = 64M
max_heap_table_size = 64M" >> /etc/my.cnf
service mariadb restart

PHP_VERSIONS=("5.6" "7.0" "7.1" "7.2" "7.3" "7.4" "8.0" "8.1" "8.2")

for version in "${PHP_VERSIONS[@]}"
do
    /usr/local/cpanel/bin/rebuild_phpconf --default=$version
    
    PHP_INI_PATH="/opt/cpanel/ea-php$version/root/etc/php.ini"
    
    sed -i 's/memory_limit = .*/memory_limit = 256M/' $PHP_INI_PATH
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' $PHP_INI_PATH
    sed -i 's/max_input_time = .*/max_input_time = 300/' $PHP_INI_PATH
    sed -i 's/post_max_size = .*/post_max_size = 100M/' $PHP_INI_PATH
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' $PHP_INI_PATH
    sed -i 's/max_file_uploads = .*/max_file_uploads = 20/' $PHP_INI_PATH
    sed -i 's/;date.timezone.*/date.timezone = "Europe\/Istanbul"/' $PHP_INI_PATH
    
    PHP_FPM_CONF_PATH="/opt/cpanel/ea-php$version/root/etc/php-fpm.conf"
    
    if [ -f $PHP_FPM_CONF_PATH ]; then
        sed -i 's/pm.max_children.*/pm.max_children = 50/' $PHP_FPM_CONF_PATH
        sed -i 's/pm.start_servers.*/pm.start_servers = 10/' $PHP_FPM_CONF_PATH
        sed -i 's/pm.min_spare_servers.*/pm.min_spare_servers = 5/' $PHP_FPM_CONF_PATH
        sed -i 's/pm.max_spare_servers.*/pm.max_spare_servers = 20/' $PHP_FPM_CONF_PATH
        sed -i 's/;pm.max_requests.*/pm.max_requests = 500/' $PHP_FPM_CONF_PATH
    fi
done
for version in "${PHP_VERSIONS[@]}"
do
    PHP_INI_PATH="/opt/cpanel/ea-php$version/root/etc/php.ini"
    
    sed -i '/disable_functions =/ s/$/,shell_exec,symlink,restore_ini,hopenbasedir,f_open,system,dl,passthru,cat exec,popen,proc_close,proc_get_status,proc_nice,proc_open,escapeshellcmd,escapeshellarg,show_source,posix_mkfifo,mysql_list_dbs,get_current_user,getmyuid,pconnect,link,symlink,pcntl_exec,leak,apache_child_terminate,posix_kill,posix_setpgid,posix_setsid,posix_setuid,proc_terminate,syslog,fpassthru,socket_select,socket_create,socket_create_listen,socket_create_pair,socket_listen,socket_accept,socket_bind,foreach,socket_strerror,pcntl_fork,pcntl_signal,pcntl_waitpid,pcntl_wexitstatus,pcntl_wifexited,pcntl_wifsignaled,pcntl_wifstopped,pcntl_wstopsig,pcntl_wtermsig,openlog,apache_get_modules,apache_get_version,apache_getenv,apache_note,apache_setenv,virtual,mail,phpmail/' $PHP_INI_PATH
done

PERL_OPTIMIZE_FILE="/var/cpanel/perl5/lib/perl5/cPanel/ConfigOptimizer.pm"
sed -i 's/^#\[backup\]/\[backup\]/' $PERL_OPTIMIZE_FILE
sed -i 's/^#disablebackup=0/disablebackup=1/' $PERL_OPTIMIZE_FILE
sed -i 's/^#skipcpbackup=0/skipcpbackup=1/' $PERL_OPTIMIZE_FILE

cd /usr/local/cpanel/whostmgr/docroot/cgi/
./easyapache4 --build
/scripts/restartsrv_httpd
cagefsctl --enable

cagefsctl --remount-all

/usr/sbin/selectorctl --enable-versions=ea-php56,ea-php70,ea-php71,ea-php72,ea-php73,ea-php74,ea-php80,ea-php81,ea-php82

echo "net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096
fs.file-max = 65536
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.shmmax = 68719476736
kernel.shmall = 4294967296" >> /etc/sysctl.conf
sysctl -p

echo "fs.file-max = 65536" >> /etc/security/limits.conf
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

sed -i 's/ServerTokens .*/ServerTokens Prod/' /etc/apache2/conf/httpd.conf
sed -i 's/ServerSignature .*/ServerSignature Off/' /etc/apache2/conf/httpd.conf
sed -i 's/TraceEnable .*/TraceEnable Off/' /etc/apache2/conf/httpd.conf

sed -i 's/expose_php = .*/expose_php = Off/' /etc/php.ini
echo "Options -FollowSymLinks -Indexes" >> /etc/httpd/conf/httpd.conf

SSH_PORT=2220
LSWS_PORT=7080

sed -i "s/^TCP_IN =.*/TCP_IN = \"20,21,22,$SSH_PORT,25,53,80,110,143,443,465,587,993,995,2077,2078,2082,2083,2086,2087,2095,2096,3306,5432,5900\"/" /etc/csf/csf.conf
sed -i "s/^TCP_OUT =.*/TCP_OUT = \"20,21,22,$SSH_PORT,25,53,80,110,113,443,2077,2078,2089,2703\"/" /etc/csf/csf.conf

sed -i "s/^TCP_IN =.*/TCP_IN = \"20,21,22,$SSH_PORT,25,53,80,110,143,443,465,587,993,995,2077,2078,2082,2083,2086,2087,2095,2096,$LSWS_PORT,3306,5432,5900\"/" /etc/csf/csf.conf
sed -i "s/^TCP_OUT =.*/TCP_OUT = \"20,21,22,$SSH_PORT,25,53,80,110,113,443,2077,2078,2089,2703,$LSWS_PORT\"/" /etc/csf/csf.conf

curl -o /etc/csf/csf.allow https://raw.githubusercontent.com/csadigital/cPanel-Auto-Config/main/csf.allow


sed -i 's/^ALWAYS_ADD_DNSSEC_FOR_ZONES=yes/ALWAYS_ADD_DNSSEC_FOR_ZONES=no/' /var/cpanel/cpanel.config
sed -i 's/^ALLOW_IP_ADD=2/ALLOW_IP_ADD=0/' /var/cpanel/cpanel.config
sed -i 's/^ALLOW_ISP_CONFIG=0/ALLOW_ISP_CONFIG=1/' /var/cpanel/cpanel.config
sed -i 's/^CPANEL=1/CPANEL=0/' /var/cpanel/cpanel.config
sed -i 's/^USE_CPANEL_STYLE=1/USE_CPANEL_STYLE=0/' /var/cpanel/cpanel.config
sed -i 's/^DISABLE_POP3S=0/DISABLE_POP3S=1/' /var/cpanel/cpanel.config
sed -i 's/^DISABLE_IMAPS=0/DISABLE_IMAPS=1/' /var/cpanel/cpanel.config
sed -i 's/^EMAIL_ALLOW_USER_CONFIG=1/EMAIL_ALLOW_USER_CONFIG=0/' /var/cpanel/cpanel.config

/scripts/restartsrv_cpsrvd

# Cron işleri
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -u $user -l | grep -v '^#' | grep -v '^$' > /tmp/cronjobs.tmp
    crontab -u $user /tmp/cronjobs.tmp
    rm -f /tmp/cronjobs.tmp
done

echo "expose_php = Off
disable_functions = show_source, system, shell_exec, passthru, exec, phpinfo, popen, proc_open, allow_url_fopen
enable_dl = Off
max_input_vars = 1000
open_basedir = /home:/tmp:/var/tmp:/usr/local/lib/php/
max_execution_time = 60
max_input_time = 60
post_max_size = 32M
upload_max_filesize = 32M
memory_limit = 256M
file_uploads = On
session.cookie_httponly = 1
session.use_only_cookies = 1
session.cookie_secure = 1" >> /etc/php.ini

echo "LimitRequestBody 10485760
Timeout 60
KeepAlive Off
<IfModule mod_reqtimeout.c>
  RequestReadTimeout header=20-40,MinRate=500 body=20,MinRate=500
</IfModule>" >> /etc/httpd/conf/httpd.conf

echo "mod_evasive settings:
<IfModule mod_evasive24.c>
    DOSHashTableSize 3097
    DOSPageCount 5
    DOSSiteCount 100
    DOSPageInterval 1
    DOSSiteInterval 1
    DOSBlockingPeriod 10
    DOSEmailNotify admin@example.com
    DOSLogDir /var/log/mod_evasive
    DOSWhitelist 127.0.0.1
    DOSWhitelist 192.168.0.*
</IfModule>" >> /etc/httpd/conf/httpd.conf

echo "ModSecurity settings:
<IfModule mod_security2.c>
    SecRequestBodyAccess On
    SecRequestBodyLimit 13107200
    SecRequestBodyNoFilesLimit 131072
    SecRequestBodyInMemoryLimit 131072
    SecResponseBodyAccess Off
    SecResponseBodyMimeType text/plain text/html text/xml
    SecResponseBodyLimit 524288
    SecServerSignature Off
    SecTmpDir /tmp
    SecDataDir /tmp
    SecAuditEngine RelevantOnly
    SecAuditLogRelevantStatus ^5
    SecAuditLogParts ABIJDEFHZ
    SecAuditLogType Serial
    SecAuditLog /var/log/httpd/modsec_audit.log
    SecDebugLog /var/log/httpd/modsec_debug.log
    SecDebugLogLevel 0
    SecAuditLogStorageDir /var/log/httpd/audit/
    SecPcreMatchLimit 1000
    SecPcreMatchLimitRecursion 1000
    SecRuleEngine On
    SecRequestBodyLimitAction Reject
    SecRule REQUEST_HEADERS:Content-Type "text/xml" \
    "id:'200000',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML"
</IfModule>" >> /etc/httpd/conf/httpd.conf

echo "Symlink koruması
<Directory />
    Options -FollowSymLinks
</Directory>" >> /etc/httpd/conf/httpd.conf

cat << EOF >> /etc/csf/csf.allow
# Başlangıç CSF Allow IP Listesi
$(curl -s https://raw.githubusercontent.com/csadigital/cPanel-Auto-Config/main/csf.allow)
# Son CSF Allow IP Listesi
EOF



echo "Optimizasyon tamamlandı.
