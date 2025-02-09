#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | Lemper Manage - Simple LEMP Virtual Host Manager                        |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2022 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

# Version control.
PROG_NAME=$(basename "$0")
PROG_VER="2.x.x"
CMD_PARENT="lemper-cli"
CMD_NAME="manage"

# Make sure only root can access and not direct access.
if ! declare -F "requires_root" &>/dev/null; then
    echo "Direct access to this script is not permitted."
    exit 1
fi

##
# Main Functions
##

## 
# Show usage
# output to STDERR.
##
function show_usage() {
cat <<- EOL
${CMD_PARENT} ${CMD_NAME} ${PROG_VER}
Simple Nginx virtual host (vHost) manager,
enable/disable/remove Nginx vHost on Debian/Ubuntu Server.

Requirements:
  * LEMP stack setup uses [LEMPer](https://github.com/joglomedia/LEMPer)

Usage:
  ${CMD_PARENT} ${CMD_NAME} [OPTION]...

Options:
  -b, --enable-brotli <vhost domain name>
      Enable Brotli compression.
  -c, --enable-fastcgi-cache <vhost domain name>
      Enable FastCGI cache.
  --disable-fastcgi-cache <vhost domain name>
      Disable FastCHI cache.
  -d, --disable <vhost domain name>
      Disable virtual host.
  -e, --enable <vhost domain name>
      Enable virtual host.
  -f, --enable-fail2ban <vhost domain name>
      Enable fail2ban jail.
  --disable-fail2ban <vhost domain name>
      Disable fail2ban jail.
  -g, --enable-gzip <vhost domain name>
      Enable Gzip compression.
  --disable-compression  <vhost domain name>
      Disable Gzip/Brotli compression.
  -p, --enable-pagespeed <vhost domain name>
      Enable Mod PageSpeed.
  --disable-pagespeed <vhost domain name>
      Disable Mod PageSpeed.
  -r, --remove <vhost domain name>
      Remove virtual host configuration.
  -s, --enable-ssl <vhost domain name>
      Enable HTTP over SSL with Let's Encrypt.
  --disable-ssl <vhost domain name>
      Disable HTTP over SSL.
  --remove-ssl <vhost domain name>
      Remove SSL certificate.
  --renew-ssl <vhost domain name>
      Renew SSL certificate.

  -h, --help
      Print this message and exit.
  -v, --version
      Output version information and exit.

Example:
  ${CMD_PARENT} ${CMD_NAME} --remove example.com

For more informations visit https://masedi.net/lemper
Mail bug reports and suggestions to <me@masedi.net>
EOL
}

##
# Enable vhost.
##
function enable_vhost() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Enabling virtual host: ${DOMAIN}..."

    # Enable Nginx's vhost config.
    if [[ ! -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" && -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]]; then
        run ln -s "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
        success "Your virtual host ${DOMAIN} has been enabled..."
        reload_nginx
    else
        fail "${DOMAIN} couldn't be enabled. Probably, it has been enabled or not created yet."
        exit 1
    fi
}

##
# Disable vhost.
##
function disable_vhost() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling virtual host: ${DOMAIN}..."

    # Disable Nginx's vhost config.
    if [[ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]]; then
        run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"
        success "Your virtual host ${DOMAIN} has been disabled..."
        reload_nginx
    else
        fail "${DOMAIN} couldn't be disabled. Probably, it has been disabled or removed."
        exit 1
    fi
}

##
# Remove vhost.
##
function remove_vhost() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Removing virtual host is not reversible."
    read -t 30 -rp "Press [Enter] to continue..." </dev/tty

    # Get web root path from vhost config, first.
    local WEBROOT && \
    WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

    # Remove Nginx's vhost config.
    [[ -f "/etc/nginx/sites-enabled/${DOMAIN}.conf" ]] && \
        run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]] && \
        run rm -f "/etc/nginx/sites-available/${DOMAIN}.conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]] && \
        run rm -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf"

    [[ -f "/etc/nginx/sites-available/${DOMAIN}.ssl-conf" ]] && \
        run rm -f "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

    [[ -f "/etc/lemper/vhost.d/${DOMAIN}.conf" ]] && \
        run rm -f "/etc/lemper/vhost.d/${DOMAIN}.conf"

    # If we have local domain setup in hosts file, remove it.
    if grep -qwE "${DOMAIN}" "/etc/hosts"; then
        info "Domain ${DOMAIN} found in your hosts file. Removing now...";
        run sed -i".backup" "/${DOMAIN}/d" "/etc/hosts"
    fi

    success "Virtual host configuration file removed."

    # Remove vhost root directory.
    read -rp "Do you want to delete website root directory? [y/n]: " -e DELETE_DIR

    # Fix web root path for framework apps that use 'public' directory.
    WEBROOT=$(echo "${WEBROOT}" | sed '$ s|\/public$||')

    if [[ "${DELETE_DIR}" == Y* || "${DELETE_DIR}" == y* ]]; then
        if [[ ! -d "${WEBROOT}" ]]; then
            read -rp "Enter real path to website root directory: " -i "${WEBROOT}" -e WEBROOT
        fi

        if [[ -d "${WEBROOT}" ]]; then
            run rm -fr "${WEBROOT}"
            success "Virtual host root directory removed."
        else
            info "Sorry, directory couldn't be found. Skipped..."
        fi
    fi

    # Drop MySQL database.
    read -rp "Do you want to Drop database associated with this domain? [y/n]: " -e DROP_DB
    if [[ "${DROP_DB}" == Y* || "${DROP_DB}" == y* ]]; then
        until [[ "${MYSQL_USER}" != "" ]]; do
			read -rp "MySQL Username: " -e MYSQL_USER
		done

        until [[ "${MYSQL_PASS}" != "" ]]; do
			echo -n "MySQL Password: "; stty -echo; read -r MYSQL_PASS; stty echo; echo
		done

        echo ""
        echo "Please select your database below!"
        echo "+-------------------------------+"
        echo "|         Database name          "
        echo "+-------------------------------+"

        # Show user's databases
        #run mysql -u "${MYSQL_USER}" -p"${MYSQL_PASS}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema"
        local DATABASES && \
        DATABASES=$(mysql -u "${MYSQL_USER}" -p"${MYSQL_PASS}" -e "SHOW DATABASES;" | grep -vE "Database|mysql|*_schema")

        if [[ -n "${DATABASES}" ]]; then
            printf '%s\n' "${DATABASES}"
        else
            echo "No database found."
        fi

        echo "+----------------------+"

        until [[ "${DBNAME}" != "" ]]; do
            read -rp "MySQL Database: " -e DBNAME
		done

        if [[ -d "/var/lib/mysql/${DBNAME}" ]]; then
            echo "Deleting database ${DBNAME}..."
            run mysql -u "${MYSQL_USER}" -p"${MYSQL_PASS}" -e "DROP DATABASE ${DBNAME}"
            success "Database '${DBNAME}' dropped."
        else
            info "Sorry, database ${DBNAME} not found. Skipped..."
        fi
    fi

    echo "Virtual host ${DOMAIN} has been removed."

    # Reload Nginx.
    reload_nginx
}

##
# Enable fail2ban for virtual host.
##
function enable_fail2ban() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Enabling Fail2ban ${FRAMEWORK^} filter for ${DOMAIN}..."

    # Get web root path from vhost config, first.
    local WEBROOT && \
    WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

    if [[ ! -d ${WEBROOT} ]]; then
        read -rp "Enter real path to website root directory containing your access_log file: " -i "${WEBROOT}" -e WEBROOT
    fi

    if [[ $(command -v fail2ban-client) && -f "/etc/fail2ban/filter.d/${FRAMEWORK}.conf" ]]; then
        cat > "/etc/fail2ban/jail.d/${DOMAIN}.conf" <<EOL
[${1}]
enabled = true
port = http,https
filter = ${FRAMEWORK}
action = iptables-multiport[name=webapps, port="http,https", protocol=tcp]
logpath = ${WEBROOT}/access_log
bantime = 30d
findtime = 5m
maxretry = 3
EOL

        # Reload fail2ban
        run service fail2ban reload
        success "Fail2ban ${FRAMEWORK^} filter for ${DOMAIN} enabled."
    else
        info "Fail2ban or framework's filter is not installed. Please install it first!"
    fi
}

##
# Disable fail2ban for virtual host.
##
function disable_fail2ban() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling Fail2ban ${FRAMEWORK^} filter for ${DOMAIN}..."

    if [[ $(command -v fail2ban-client) && -f "/etc/fail2ban/jail.d/${DOMAIN}.conf" ]]; then
        run rm -f "/etc/fail2ban/jail.d/${DOMAIN}.conf"
        run service fail2ban reload
        success "Fail2ban ${FRAMEWORK^} filter for ${DOMAIN} disabled."
    else
        info "Fail2ban or framework's filter is not installed. Please install it first!"
    fi
}

##
# Enable Nginx's fastcgi cache.
##
function enable_fastcgi_cache() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Enabling FastCGI cache for ${DOMAIN}..."

    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
        # enable cached directives
        run sed -i "s|#include\ /etc/nginx/includes/rules_fastcgi_cache.conf|include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # enable fastcgi_cache conf
        run sed -i "s|#include\ /etc/nginx/includes/fastcgi_cache.conf|include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # Reload Nginx.
        reload_nginx
    else
        info "FastCGI cache is not enabled. There is no cached configuration."
        exit 1
    fi
}

##
# Disable Nginx's fastcgi cache.
##
function disable_fastcgi_cache() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling FastCGI cache for ${DOMAIN}..."

    if [ -f /etc/nginx/includes/rules_fastcgi_cache.conf ]; then
        # enable cached directives
        run sed -i "s|^\    include\ /etc/nginx/includes/rules_fastcgi_cache.conf|\    #include\ /etc/nginx/includes/rules_fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # enable fastcgi_cache conf
        run sed -i "s|^\        include\ /etc/nginx/includes/fastcgi_cache.conf|\        #include\ /etc/nginx/includes/fastcgi_cache.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"

        # Reload Nginx.
        reload_nginx
    else
        info "FastCGI cache is not enabled. There is no cached configuration."
        exit 1
    fi
}

##
# Enable Nginx's Mod PageSpeed.
##
function enable_mod_pagespeed() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Enabling Mod PageSpeed for ${DOMAIN}..."

    if [[ -f /etc/nginx/includes/mod_pagespeed.conf && -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then
        # Enable mod pagespeed.
        run sed -i "s|#include\ /etc/nginx/mod_pagespeed|include\ /etc/nginx/mod_pagespeed|g" /etc/nginx/nginx.conf
        run sed -i "s|#include\ /etc/nginx/includes/mod_pagespeed.conf|include\ /etc/nginx/includes/mod_pagespeed.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"
        run sed -i "s|#pagespeed\ EnableFilters|pagespeed\ EnableFilters|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"
        run sed -i "s|#pagespeed\ Disallow|pagespeed\ Disallow|g" "/etc/nginx/sites-available/${DOMAIN}.conf"
        run sed -i "s|#pagespeed\ Domain|pagespeed\ Domain|g" "/etc/nginx/sites-available/${DOMAIN}.conf"

        # If SSL enabled, ensure to also enable PageSpeed related vars.
        #if grep -qwE "^\    include\ /etc/nginx/includes/ssl.conf" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
        #    run sed -i "s/#pagespeed\ FetchHttps/pagespeed\ FetchHttps/g" \
        #        "/etc/nginx/sites-available/${DOMAIN}.conf"
        #    run sed -i "s/#pagespeed\ MapOriginDomain/pagespeed\ MapOriginDomain/g" \
        #        "/etc/nginx/sites-available/${DOMAIN}.conf"
        #fi

        # Reload Nginx.
        reload_nginx
    else
        info "Mod PageSpeed is not enabled. Nginx must be installed with PageSpeed module."
        exit 1
    fi
}

##
# Disable Nginx's Mod PageSpeed.
##
function disable_mod_pagespeed() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling Mod PageSpeed for ${DOMAIN}..."

    if [[ -f /etc/nginx/includes/mod_pagespeed.conf && -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then
        # Disable mod pagespeed
        #run sed -i "s|^\    include\ /etc/nginx/mod_pagespeed|\    #include\ /etc/nginx/mod_pagespeed|g" /etc/nginx/nginx.conf
        run sed -i "s|^\    include\ /etc/nginx/includes/mod_pagespeed.conf|\    #include\ /etc/nginx/includes/mod_pagespeed.conf|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"
        run sed -i "s|^\    pagespeed\ EnableFilters|\    #pagespeed\ EnableFilters|g" "/etc/nginx/sites-available/${DOMAIN}.conf"
        run sed -i "s|^\    pagespeed\ Disallow|\    #pagespeed\ Disallow|g" "/etc/nginx/sites-available/${DOMAIN}.conf"
        run sed -i "s|^\    pagespeed\ Domain|\    #pagespeed\ Domain|g" "/etc/nginx/sites-available/${DOMAIN}.conf"

        # If SSL enabled, ensure to also disable PageSpeed related vars.
        #if grep -qwE "\    include /etc/nginx/includes/ssl.conf" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
        #    run sed -i "s/^\    pagespeed\ FetchHttps/\    #pagespeed\ FetchHttps/g" \
        #        "/etc/nginx/sites-available/${DOMAIN}.conf"
        #    run sed -i "s/^\    pagespeed\ MapOriginDomain/\    #pagespeed\ MapOriginDomain/g" \
        #        "/etc/nginx/sites-available/${DOMAIN}.conf"
        #fi

        # Reload Nginx.
        reload_nginx
    else
        info "Mod PageSpeed is not enabled. Nginx must be installed with PageSpeed module."
        exit 1
    fi
}

##
# Enable HTTPS (HTTP over SSL).
##
function enable_ssl() {
    # Verify user input hostname (domain name).
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    #TODO: Generate Let's Encrypt SSL using Certbot.
    if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
        echo "Certbot: Get Let's Encrypt certificate..."

        # Get web root path from vhost config, first.
        local WEBROOT && \
        WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

        # Certbot get Let's Encrypt SSL.
        if [[ -n $(command -v certbot) ]]; then
            # Is it wildcard vhost?
            if grep -qwE "${DOMAIN}\ \*.${DOMAIN}" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                run certbot certonly --manual --manual-public-ip-logging-ok --preferred-challenges dns \
                    --server https://acme-v02.api.letsencrypt.org/directory --agree-tos \
                    --webroot-path="${WEBROOT}" -d "${DOMAIN}" -d "*.${DOMAIN}"
            else
                run certbot certonly --webroot --preferred-challenges http --agree-tos \
                    --webroot-path="${WEBROOT}" -d "${DOMAIN}"
            fi
        else
            fail "Certbot executable binary not found. Install it first!"
        fi
    fi

    # Generate Diffie-Hellman parameters.
    if [ ! -f /etc/nginx/ssl/dhparam-2048.pem ]; then
        echo "Generating Diffie-Hellman parameters for enhanced HTTPS/SSL security."

        run openssl dhparam -out /etc/nginx/ssl/dhparam-2048.pem 2048
        #run openssl dhparam -out /etc/nginx/ssl/dhparam-4096.pem 4096
    fi

    # Update vhost config.
    if [[ "${DRYRUN}" != true ]]; then
        # Ensure there is no HTTPS enabled server block.
        if ! grep -qwE "^\    listen\ 443 ssl http2" "/etc/nginx/sites-available/${DOMAIN}.conf"; then

            # Make backup first.
            run cp -f "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf"

            # Change listening port to 443.
            run sed -i "s/listen\ 80/listen\ 443 ssl http2/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s/listen\ \[::\]:80/listen\ \[::\]:443 ssl http2/g" "/etc/nginx/sites-available/${DOMAIN}.conf"

            # Enable SSL configs.
            run sed -i "s/#ssl_certificate/ssl_certificate/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s/#ssl_certificate_key/ssl_certificate_key/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s/#ssl_trusted_certificate/ssl_trusted_certificate/g" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run sed -i "s|#include\ /etc/nginx/includes/ssl.conf|include\ /etc/nginx/includes/ssl.conf|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"

            # Adjust PageSpeed if enabled.
            #if grep -qwE "^\    include\ /etc/nginx/includes/mod_pagespeed.conf" \
            #    "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            #    echo "Adjusting PageSpeed configuration..."
            #    run sed -i "s/#pagespeed\ FetchHttps/pagespeed\ FetchHttps/g" \
            #        "/etc/nginx/sites-available/${DOMAIN}.conf"
            #    run sed -i "s/#pagespeed\ MapOriginDomain/pagespeed\ MapOriginDomain/g" \
            #        "/etc/nginx/sites-available/${DOMAIN}.conf"
            #fi

            # Append redirection block.
            cat >> "/etc/nginx/sites-available/${DOMAIN}.conf" <<EOL

# HTTP to HTTPS redirection.
server {
    listen 80;
    listen [::]:80;

    ## Make site accessible from world web.
    server_name ${1};

    ## Automatically redirect site to HTTPS protocol.
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOL

            reload_nginx
        else
            warning -e "\nOops, Nginx HTTPS server block already exists. Please inspect manually for further action!"
        fi
    else
        info "Updating HTTPS config in dry run mode."
    fi
}

##
# Disable HTTPS (HTTP over SSL).
##
function disable_ssl() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    # Update vhost config.
    if [[ "${DRYRUN}" != true ]]; then
        echo "Disabling HTTPS configuration..."

        if [ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]; then
            # Disable vhost first.
            run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"

            # Backup ssl config.
            run mv "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

            # Restore non ssl config.
            run mv "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run ln -s "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-enabled/${DOMAIN}.conf"

            reload_nginx
        else
            error "Something went wrong. You still could disable HTTPS manually."
        fi
    else
        info "Disabling HTTPS config in dry run mode."
    fi
}

##
# Disable HTTPS and remove Let's Encrypt SSL certificate.
##
function remove_ssl() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    # Update vhost config.
    if [[ "${DRYRUN}" != true ]]; then
        # Disable HTTPS first.
        echo "Disabling HTTPS configuration..."

        if [ -f "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" ]; then
            # Disable vhost first.
            run unlink "/etc/nginx/sites-enabled/${DOMAIN}.conf"

            # Backup ssl config.
            run mv "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"

            # Restore non ssl config.
            run mv "/etc/nginx/sites-available/${DOMAIN}.nonssl-conf" "/etc/nginx/sites-available/${DOMAIN}.conf"
            run ln -s "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-enabled/${DOMAIN}.conf"

            reload_nginx
        else
            error "Something went wrong. You still could disable HTTPS manually."
        fi

        # Remove SSL config.
        if [ -f "/etc/nginx/sites-available/${DOMAIN}.ssl-conf" ]; then
            run rm "/etc/nginx/sites-available/${DOMAIN}.ssl-conf"
        fi

        # Remove SSL cert.
        echo "Removing SSL certificate..."

        if [[ -n $(command -v certbot) ]]; then
            run certbot delete --cert-name "${DOMAIN}"
        else
            fail "Certbot executable binary not found. Install it first!"
        fi

        reload_nginx
    else
        info "SSL certificate removed in dry run mode."
    fi
}

##
# Renew Let's Encrypt SSL certificate.
##
function renew_ssl() {
    # Verify user input hostname (domain name)
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    # Update vhost config.
    if [[ "${DRYRUN}" != true ]]; then
        echo "Renew SSL certificate..."

        # Renew Let's Encrypt SSL using Certbot.
        if [ -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
            echo "Certbot: Renew Let's Encrypt certificate..."

            # Get web root path from vhost config, first.
            local WEBROOT && \
            WEBROOT=$(grep -wE "set\ \\\$root_path" "/etc/nginx/sites-available/${DOMAIN}.conf" | awk '{print $3}' | cut -d'"' -f2)

            # Certbot get Let's Encrypt SSL.
            if [[ -n $(command -v certbot) ]]; then
                # Is it wildcard vhost?
                if grep -qwE "${DOMAIN}\ \*.${DOMAIN}" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
                    run certbot certonly --manual --agree-tos --preferred-challenges dns \
                        --server https://acme-v02.api.letsencrypt.org/directory \
                        --manual-public-ip-logging-ok --webroot-path="${WEBROOT}" -d "${DOMAIN}" -d "*.${DOMAIN}"
                else
                    run certbot renew --cert-name "${DOMAIN}" --dry-run
                fi
            else
                fail "Certbot executable binary not found. Install it first!"
            fi
        else
            info "Certificate file not found. May be your SSL is not activated yet."
        fi

        reload_nginx
    else
        info "Renew SSL certificate in dry run mode."
    fi
}

##
# Enable Brotli compression module.
##
function enable_brotli() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    if [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" && -f /etc/nginx/modules-enabled/30-mod-http-brotli-static.conf ]]; then
        echo "Enable Nginx Brotli compression..."

        if grep -qwE "^\    include\ /etc/nginx/includes/compression_brotli.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            info "Brotli compression module already enabled."
            exit 0
        elif grep -qwE "^\    include\ /etc/nginx/includes/compression_gzip.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Found Gzip compression enabled, updating to Brotli..."

            run sed -i "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_brotli.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        elif grep -qwE "^\    #include\ /etc/nginx/includes/compression_[a-z]*\.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Enabling Brotli compression module..."

            run sed -i "s|#include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_brotli.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        else
            error "Sorry, we couldn't find any compression module section."
            echo "We recommend you to enable Brotli module manually."
            exit 1
        fi

        reload_nginx
    else
        error "Sorry, we can't find Nginx and Brotli module config file"
        echo "it should be located under /etc/nginx/ directory."
        exit 1
    fi
}

##
# Enable Gzip compression module,
# enabled by default.
##
function enable_gzip() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    if [[ -f "/etc/nginx/sites-available/${DOMAIN}.conf" && -f /etc/nginx/includes/compression_gzip.conf ]]; then
        echo "Enable Nginx Gzip compression..."

        if grep -qwE "^\    include\ /etc/nginx/includes/compression_gzip.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            info "Gzip compression module already enabled."
            exit 0
        elif grep -qwE "^\    include\ /etc/nginx/includes/compression_brotli.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Found Brotli compression enabled, updating to Gzip..."

            run sed -i "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_gzip.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        elif grep -qwE "^\    #include\ /etc/nginx/includes/compression_[a-z]*\.conf;" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
            echo "Enabling Gzip compression module..."

            run sed -i "s|#include\ /etc/nginx/includes/compression_[a-z]*\.conf;|include\ /etc/nginx/includes/compression_gzip.conf;|g" \
                "/etc/nginx/sites-available/${DOMAIN}.conf"
        else
            error "Sorry, we couldn't find any compression module section."
            echo "We recommend you to enable Gzip module manually."
            exit 1
        fi

        reload_nginx
    else
        error "Sorry, we can't find Nginx config file"
        echo "it should be located under /etc/nginx/ directory."
        exit 1
    fi
}

##
# Disable Gzip/Brotli compression module
##
function disable_compression() {
    local DOMAIN=${1}
    verify_vhost "${DOMAIN}"

    echo "Disabling compression module..."

    if grep -qwE "^\    include\ /etc/nginx/includes/compression_[a-z]*\.conf" "/etc/nginx/sites-available/${DOMAIN}.conf"; then
        run sed -i "s|include\ /etc/nginx/includes/compression_[a-z]*\.conf;|#include\ /etc/nginx/includes/compression_gzip.conf;|g" \
            "/etc/nginx/sites-available/${DOMAIN}.conf"
    else
        error "Sorry, we couldn't find any enabled compression module."
        exit 1
    fi

    reload_nginx
}

##
# Verify if virtual host exists.
##
function verify_vhost() {
    if [[ -z "${1}" ]]; then
        error "Virtual host (vhost) or domain name is required."
        echo "See '${PROG_NAME} --help' for more information."
        exit 1
    fi

    if [[ "${1}" == "default" ]]; then
        error "Modify/delete default virtual host is prohibitted."
        exit 1
    fi

    if [[ ! -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]]; then
        error "Sorry, we couldn't find Nginx virtual host: ${1}..."
        exit 1
    fi
}

##
# Reload Nginx safely.
##
function reload_nginx() {
    # Reload Nginx
    echo "Reloading Nginx configuration..."

    if [[ -e /var/run/nginx.pid ]]; then
        if nginx -t > /dev/null 2>&1; then
            service nginx reload -s > /dev/null 2>&1
        else
            error "Configuration couldn't be validated. Please correct the error below:";
            nginx -t
            [[ ${EXIT} ]] && exit 1
        fi
    # Nginx service dead? Try to start it.
    else
        if [[ -n $(command -v nginx) ]]; then
            if nginx -t 2>/dev/null > /dev/null; then
                service nginx restart > /dev/null 2>&1
            else
                error "Configuration couldn't be validated. Please correct the error below:";
                nginx -t
                exit 1
            fi
        else
            info "Something went wrong with your LEMP stack installation."
            exit 1
        fi
    fi

    if [[ $(pgrep -c nginx) -gt 0 ]]; then
        success "Your change has been successfully applied."
        exit 0
    else
        fail "An error occurred when updating configuration.";
    fi
}


##
# Main Manage CLI Wrapper
##
function init_lemper_manage() {
    OPTS=$(getopt -o c:d:e:f:p:r:s:bghv \
      -l enable:,disable:,remove:,enable-fail2ban:,disable-fail2ban:,enable-fastcgi-cache:,disable-fastcgi-cache: \
      -l enable-pagespeed:,disable-pagespeed:,enable-ssl:,disable-ssl:,remove-ssl:,renew-ssl: \
      -l enable-brotli:,enable-gzip:,disable-compression:,help,version \
      -n "${PROG_NAME}" -- "$@")

    eval set -- "${OPTS}"

    while true
    do
        case "${1}" in
            -e | --enable)
                enable_vhost "${2}"
                shift 2
            ;;
            -d | --disable)
                disable_vhost "${2}"
                shift 2
            ;;
            -r | --remove)
                remove_vhost "${2}"
                shift 2
            ;;
            -c | --enable-fastcgi-cache)
                enable_fastcgi_cache "${2}"
                shift 2
            ;;
            --disable-fastcgi-cache)
                disable_fastcgi_cache "${2}"
                shift 2
            ;;
            -f | --enable-fail2ban)
                enable_fail2ban "${2}"
                shift 2
            ;;
            --disable-fail2ban)
                disable_fail2ban "${2}"
                shift 2
            ;;
            -p | --enable-pagespeed)
                enable_mod_pagespeed "${2}"
                shift 2
            ;;
            --disable-pagespeed)
                disable_mod_pagespeed "${2}"
                shift 2
            ;;
            -s | --enable-ssl)
                enable_ssl "${2}"
                exit
                shift 2
            ;;
            --disable-ssl)
                disable_ssl "${2}"
                exit
                shift 2
            ;;
            --remove-ssl)
                remove_ssl "${2}"
                exit
                shift 2
            ;;
            --renew-ssl)
                renew_ssl "${2}"
                exit
                shift 2
            ;;
            -b | --enable-brotli)
                enable_brotli "${2}"
                shift 2
            ;;
            -g | --enable-gzip)
                enable_gzip "${2}"
                shift 2
            ;;
            --disable-compression)
                disable_compression "${2}"
                shift 2
            ;;
            -h | --help)
                show_usage
                exit 0
                shift 2
            ;;
            -v | --version)
                echo "${PROG_NAME} version ${PROG_VER}"
                exit 0
                shift 2
            ;;
            --) shift
                break
            ;;
            *)
                fail "Invalid argument: ${1}"
                exit 1
            ;;
        esac
    done

    echo "${PROG_NAME}: missing required argument"
    echo "See '${PROG_NAME} --help' for more information."
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_lemper_manage "$@"
