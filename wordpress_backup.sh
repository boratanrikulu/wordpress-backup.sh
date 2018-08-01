#!/bin/bash
# /opt/scripts/backup.sh

BACKUP_DIR='/srv/backup'
BACKUP_SERV='192.168.42.78'
BACKUP_SERV_PORT='22'

die() {
        echo "$*" >&2
        exit 234 # error olarak çıktığını belirtmek için 0 hariç bir şey gireriz
}

warn() {
        echo "$*" >&1
}

check_service() {
        declare -a service_list=("httpd" "mysqld")

        stat=0
        for i in "${service_list[@]}"; do
                spid=$(pgrep -x $i)
                # ya da bu şekilde ağır bi şekilde yapabilirdik
                # systemctl --system -all | grep mariadb | awk -F ' ' '{print $4}'
                if [[ -z $spid ]]; then
                        stat+=1
                        warn "$i çalışmıyor."
                fi
        done

        if [[ "$stat" -gt "0" ]]; then
                die "Program sonlandırıldı."
        fi
}

db_backup() {
        db_backup_dir="$BACKUP_DIR/db"
        date=$(date +%Y%m%d_%H-%M)
        dumpname="all_db.-$date.sql"
        if [[ ! -d $db_backup_dir ]]; then
                mkdir $db_backup_dir || die "$db_backup_dir oluşturulamadı."
        fi

        mysqldump -A -C -x > $db_backup_dir/$dumpname 2> /dev/null || die "$db_backup_dir/$dumpname dökümü alınamadı."

        if [[ -f $db_backup_dir/$dumpname ]]; then
                gzip $db_backup_dir/$dumpname || die "$db_backup_dir/$dumpname sıkıştırılamadı"
        fi
}

wp_backup() {
        wp_dir='/var/www/html'
        # tek tırnak hepsini string olarak kabul eder
        date=$(date +%Y%m%d_%H-%M)
        wp_backup_dir="$BACKUP_DIR/wp"
        compress="$(rpm -qa bzip2)"
        if [[ ! -d $wp_backup_dir ]]; then
                mkdir $wp_backup_dir || die "$wp_backup_dir oluşturulamadı."
        fi

        cp -a $wp_dir $wp_backup_dir/wordpress || die "$wp_dir dizini $wp_backup_dir/wordpress dizinine kopyalanamadı."
        # wordpress dizinin o sırada işlem yapılabileceği için direkt tar yapmak yerine önce cp'ledik.

        if [[ -d $wp_backup_dir ]]; then
                if [[ ! -z $compress ]]; then
                        tar -cjf ${wp_backup_dir}/wordpress-$date.tar.bz2 $wp_backup_dir/wordpress >/dev/null 2>&1 || die "${wp_backup_dir}/wordpress-$date.tar.bz2 oluşturulamadı."
                else
                        tar -czf ${wp_backup_dir}/wordpress-$date.tar.gz $wp_backup_dir/wordpress >/dev/null 2>&1 || die "${wp_backup_dir}/wordpress-$date.tar.gz oluşturulamadı."
                fi
                rm -rf $wp_backup_dir/wordpress
        fi
}

httpd_backup() {
        apache_conf_dir='/etc/httpd/conf'
        apache_backup_dir="$BACKUP_DIR/apache"
        date=$(date +%Y%m%d_%H-%M)

        if [[ ! -d $apache_backup_dir ]]; then
                mkdir $apache_backup_dir || die "$apache_backup_dir oluşturulamadı."
        fi

        tar -czf $apache_backup_dir/apcahe-$date.tar.gz $apache_conf_dir >/dev/null 2>&1 || die "$apache_backup_dir/apache-$date.tar.gz oluşturulamadı."
}

sync_all() {
        nc -z $BACKUP_SERV $BACKUP_SERV_PORT >/dev/null 2>&1 || die "$BACKUP_SERV_PORT portu $BACKUP_SERV üzerinde kapalı."
        tar -czf $BACKUP_DIR/all.tar.gz $BACKUP_DIR/apache $BACKUP_DIR/wp $BACKUP_DIR/db >/dev/null 2>&1 || die "$BACKUP_DIR/all.tar.gz oluşturulamadı."
        if [[ -e $BACKUP_DIR/all.tar.gz ]]; then
                # scp -i $BACKUP_DIR/all.tar.gz $BACKUP_SERV:$BACKUP_DIR || die "$BACKUP_SERV için sync işlemi başarısız oldu."
                rsync -az $BACKUP_DIR/all.tar.gz $BACKUP_SERV:$BACKUP_DIR || die "$BACKUP_SERV için sync işlemi başarısız oldu."
        fi
}

main() {
        if [[ ! -d $BACKUP_DIR ]]; then
                mkdir $BACKUP_DIR 2>/dev/null || die "$BACKUP_DIR oluşturulamadı."
                # mkdir hata mesajı üretirse /dev/null'a yollanır               
        fi
        warn "$BACKUP_DIR sistemde mevcut. Devam ediliyor..."
        check_service
        db_backup
        wp_backup
        httpd_backup
        sync_all
}

if [[ $EUID == 0 ]]; then
        main # root tarafından çalıştırılıyor ise main fonksiyonu çalıştırılır.
else
        die "$0 sadece root yetkisi ile çalışmaktadır."
fi
