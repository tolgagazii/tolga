#!/bin/sh

# BETIK BILGILENDIRME
# Notepad++ da Düzen > Satır Sonunu Dönüştür > UNIX (LF)

update_zapret2_parameters() {
    if [ -f "/opt/zapret2/config" ]; then
        sed -i 's/^DISABLE_IPV6=1/DISABLE_IPV6=0/' /opt/zapret2/config
        sed -i 's/^MODE_FILTER=.*/MODE_FILTER=autohostlist/' /opt/zapret2/config
        sed -i 's/^NFQWS2_ENABLE=.*/NFQWS2_ENABLE=1/' /opt/zapret2/config
        sed -i 's/^#*WS_USER=.*/WS_USER=nobody/' /opt/zapret2/config
    fi

    sed -i '/^NFQWS2_OPT="/,/^"$/c\
NFQWS2_OPT="--filter-tcp=80 <HOSTLIST> --filter-l7=http --payload=http_req --lua-desync=fake:blob=fake_default_http:ip_ttl=2:ip6_ttl=2:repeats=1 --new --filter-tcp=443 <HOSTLIST> --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:ip_ttl=2:ip6_ttl=2:repeats=1 --new --filter-udp=443 <HOSTLIST> --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:ip_ttl=2:ip6_ttl=2:repeats=6 "' /opt/zapret2/config && echo "Zapret2 parametreleri lua stratejisine ve autohostlist moduna göre başarıyla güncellendi." || echo "UYARI: Zapret2 config güncellenemedi, dosyayı kontrol edin."

    return 0
}

allow_firewall() {
    echo '#!/bin/sh
[ "$table" != "mangle" ] && [ "$table" != "nat" ] && exit 0
/opt/zapret2/init.d/sysv/zapret2 restart-fw
exit 0' > /opt/etc/ndm/netfilter.d/000-zapret2.sh || {
        echo "HATA: Güvenlik duvarı izni verilirken hata oluştu."
        return 1
    }
	
    chmod +x /opt/etc/ndm/netfilter.d/000-zapret2.sh || {
        echo "HATA: Güvenlik duvarı izni dosyasına çalıştırma izni verilemedi."
        return 1
    }
    
    echo "Güvenlik duvarı izni verildi."
    return 0
}

add_auto_start_zapret2() {
    ln -fs /opt/zapret2/init.d/sysv/zapret2 /opt/etc/init.d/S90-zapret2 && echo "Zapret2 otomatik başlatılması etkinleştirildi." || { echo "UYARI: Zapret2 otomatik başlatılması etkinleştirilemedi."; return 0; }
}

disable_total_packet() {
    echo '#!/bin/sh

start() {
    echo "Netfilter checksum kontrolü devre dışı bırakılıyor (nf_conntrack_checksum=0)..."
    sysctl -w net.netfilter.nf_conntrack_checksum=0 &> /dev/null
    echo "Checksum kontrolü kapatıldı."
}

stop() {
    echo "Netfilter checksum kontrolü etkinleştiriliyor (nf_conntrack_checksum=1)..."
    sysctl -w net.netfilter.nf_conntrack_checksum=1 &> /dev/null
    echo "Checksum kontrolü açıldı."
}

status() {
    current_val=$(sysctl -n net.netfilter.nf_conntrack_checksum 2>/dev/null)
    if [ "$current_val" = "0" ]; then
        echo "Durum: Devre dışı (Checksum doğrulaması kapalı - Zapret2/UDP uyumlu)."
    else
        echo "Durum: Etkin (Checksum doğrulaması açık)."
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    status)
        status
        ;;
    *)
        stop
        start
        ;;
esac
exit 0' > /opt/etc/init.d/S00fix || {
        echo "HATA: Toplam paket kontrolü devre dışı bırakılırken hata oluştu."
        return 1
    }

    chmod +x /opt/etc/init.d/S00fix || {
        echo "HATA: Toplam paket kontrolü dosyasına çalıştırma izni verilemedi."
        return 1
    }
    
    echo "Toplam paket kontrolü devre dışı bırakıldı."
    return 0
}

is_zapret2_running() {
    pgrep -f "nfqws2" > /dev/null
}

is_zapret2_installed() {
    [ -f "/opt/zapret2/init.d/sysv/zapret2" ]
}

start_zapret2() {
    ! is_zapret2_installed && echo "Zapret2 yüklü değil." && return 1
    is_zapret2_running && echo "Zapret2 servisi zaten çalışıyor." && return 0
    /opt/zapret2/init.d/sysv/zapret2 start && echo "Zapret2 servisi başlatıldı." || { echo "HATA: Zapret2 başlatılamadı."; return 1; }
}

stop_zapret2() {
    ! is_zapret2_installed && echo "Zapret2 yüklü değil." && return 1
    ! is_zapret2_running && echo "Zapret2 servisi zaten durdurulmuş." && return 0
    /opt/zapret2/init.d/sysv/zapret2 stop && echo "Zapret2 servisi durduruldu." || { echo "HATA: Zapret2 durdurulamadı."; return 1; }
}

restart_zapret2() {
    ! is_zapret2_installed && echo "Zapret2 yüklü değil." && return 1
    /opt/zapret2/init.d/sysv/zapret2 restart && echo "Zapret2 servisi yeniden başlatıldı." || { echo "HATA: Zapret2 yeniden başlatılamadı."; return 1; }
}

cleanup_files_after_extracted() {
    echo "Gereksiz binary dosyaları temizleniyor..."
    for file in \
        /opt/zapret2/binaries/mac64 \
        /opt/zapret2/binaries/linux-ppc \
        /opt/zapret2/binaries/linux-lexra \
        /opt/zapret2/binaries/linux-x86 \
        /opt/zapret2/binaries/linux-x86_64 \
        /opt/zapret2/binaries/freebsd-x86_64 \
        /opt/zapret2/binaries/android-arm \
        /opt/zapret2/binaries/android-arm64 \
        /opt/zapret2/binaries/android-x86 \
        /opt/zapret2/binaries/android-x86_64 \
        /opt/zapret2/binaries/windows-x86 \
        /opt/zapret2/binaries/windows-x86_64
    do
        [ -e "$file" ] && rm -rf "$file"
    done
    echo "Gereksiz dosyalar temizlendi."
}

cleanup_files_after_uninstall() {
    rm -rf /opt/zapret2 \
           /opt/etc/init.d/S00fix \
           /opt/etc/init.d/S90-zapret2 \
           /opt/etc/ndm/netfilter.d/000-zapret2.sh &>/dev/null  
    return 0
}

uninstall_zapret2() {
    ! is_zapret2_installed && { echo "Zapret2 yüklü değil."; return 1; }

    read -r -p "Zapret2'yi kaldırmak istediğinizden emin misiniz? (e/h): " uninstall_confirmation
    [[ ! "$uninstall_confirmation" =~ ^[eE]$ ]] && { echo "Kaldırma işlemi iptal edildi."; return 0; }

    is_zapret2_running && stop_zapret2

    echo "Zapret2 kaldırılıyor..."
    if ! echo "y" | /opt/zapret2/uninstall_easy.sh &> /dev/null; then
        echo "Kaldırma betiği çalıştırılamadı, manuel temizlik yapılıyor..."
    fi

    cleanup_files_after_uninstall
    echo "Zapret2 başarıyla kaldırıldı."
    read -p "Devam etmek için Enter'a basın..."
    clear
    return 0
}

install_zapret2() {
    is_zapret2_installed && echo "Zapret2 zaten yüklü." && return 1

    echo "OPKG paketleri denetleniyor..."
    opkg update >/dev/null 2>&1
    opkg install coreutils-sort curl grep gzip ipset iptables kmod_ndms xtables-addons_legacy jq >/dev/null 2>&1 || { echo "HATA: Gerekli paketler yüklenemedi."; return 1; }
    
    DIR="/opt/zapret2"
    mkdir -p /opt/tmp

    echo "Eski kurulan/indirilen geçici arşiv dosyaları temizleniyor..."
    rm -rf /opt/tmp/zapret2-*.tar.gz /opt/tmp/zapret-*.tar.gz

    echo "GitHub üzerinden bol-van/zapret2 en son sürüm sorgulanıyor (-openwrt-embedded.tar.gz)..."
    TARBALL_URL=$(curl -s https://api.github.com/repos/bol-van/zapret2/releases/latest | grep "browser_download_url" | grep "openwrt-embedded.tar.gz" | cut -d '"' -f 4)

    if [ -z "$TARBALL_URL" ]; then
        echo "HATA: -openwrt-embedded.tar.gz uzantılı arşivi indirme bağlantısı bulunamadı!"
        return 1
    fi

    ARCHIVE="/opt/tmp/zapret2-embedded.tar.gz"
    echo "En son sürüm indiriliyor: $TARBALL_URL"
    curl -L -o "$ARCHIVE" "$TARBALL_URL" || { echo "HATA: Arşiv indirilemedi."; return 1; }

    echo "Arşiv kuruluyor..."
    rm -rf "$DIR"

    tar -xzf "$ARCHIVE" -C /opt/tmp >/dev/null 2>&1 || { echo "HATA: Arşiv açılamadı."; return 1; }

    EXTRACTED_DIR=$(tar -tf "$ARCHIVE" | head -n 1 | cut -d/ -f1)
    
    if [ -n "$EXTRACTED_DIR" ] && [ -d "/opt/tmp/$EXTRACTED_DIR" ]; then
        rm -rf "$DIR"
        mv "/opt/tmp/$EXTRACTED_DIR" "$DIR" || { echo "HATA: Dosya taşınamadı."; return 1; }
    else
        FOUND_DIR=$(ls -d /opt/tmp/zapret2-* /opt/tmp/zapret-* 2>/dev/null | grep -v "\.tar\.gz$" | head -n 1)
        if [ -n "$FOUND_DIR" ] && [ -d "$FOUND_DIR" ]; then
            rm -rf "$DIR"
            mv "$FOUND_DIR" "$DIR" || { echo "HATA: Dosya taşınamadı."; return 1; }
        else
            echo "HATA: Çıkartılan dizin bulunamadı."
            return 1
        fi
    fi

    echo "Zapret2 başarıyla yüklendi."

    cleanup_files_after_extracted

    echo "İndirilen geçici arşiv dosyası siliniyor..."
    rm -f "$ARCHIVE"

    echo "Zapret2 kurulum betiği çalıştırılıyor..."
    (
        echo "y"
        echo "1"
        echo "n"
        echo "1"
        echo "n"
        echo "n"
        echo "y"
        echo "n"
        echo "1"
        echo "1"
    ) | /opt/zapret2/install_easy.sh &> /dev/null || { echo "UYARI: install_easy.sh uyarı verdi, yapılandırmaya devam ediliyor..."; }
    
    echo "Zapret2 Keenetic yapılandırmaları uygulanıyor..."

    update_zapret2_parameters
    disable_total_packet
    allow_firewall
    add_auto_start_zapret2

    echo "Zapret2 başarıyla kuruldu ve yapılandırıldı."

    restart_zapret2
    read -p "Devam etmek için Enter'a basın..."
    clear
    return 0
}

display_menu() {
    echo "=================================================="
    echo " Keenetic için Zapret2 Yönetim ve Kurulum Scripti"
    echo " Yapımcı     : TolgaGazi"
    echo "=================================================="
    echo " 1. Zapret2'yi En Son Sürüm İndir ve Kur"
    echo " 2. Zapret2'yi Kaldır"
    echo " 3. Zapret2'yi Başlat"
    echo " 4. Zapret2'yi Durdur"
    echo " 5. Zapret2'yi Yeniden Başlat"
    echo " 6. Parametreleri ve Config'i Güncelle"
    echo " 0. Çıkış"
    echo "--------------------------------------------------"
    printf " Seçiminizi yapın (0-6): "
}

main_menu_loop() {
    while true; do
        display_menu
        read -r choice
        echo ""
        case "$choice" in
            1)
                install_zapret2
                ;;
            2)
                uninstall_zapret2
                ;;
            3)
                start_zapret2
                ;;
            4)
                stop_zapret2
                ;;
            5)
                restart_zapret2
                ;;
            6)
                update_zapret2_parameters
                restart_zapret2
                ;;
            0)
                echo "Çıkış yapılıyor..."
                break
                ;;
            *)
                echo "Geçersiz seçim! Lütfen 0 ile 6 arasında bir sayı girin."
                ;;
        esac
        echo ""
    done
}

main_menu_loop