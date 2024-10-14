#!/bin/bash

set -o pipefail
set +H
set +e

: ${PAAS_PATH:="/data/paas"}
: ${DB_CHARACTER_SET:="utf8mb4"}
: ${DB_CHARACTER_COLLATE:="utf8mb4_bin"}

# 检查mysql数据库变量
check_variables_mysql() {
    if [ ! -n "${DB_SERVER_SOCKET}" ]; then
        : ${DB_SERVER_HOST:="127.0.0.1"}
        : ${DB_SERVER_PORT:="3306"}
    fi

    USE_DB_ROOT_USER=false
    CREATE_DB_USER=false
    file_env MYSQL_USER
    file_env MYSQL_PASSWORD

    file_env MYSQL_ROOT_USER
    file_env MYSQL_ROOT_PASSWORD

    if [ ! -n "${MYSQL_USER}" ] && [ "${MYSQL_RANDOM_ROOT_PASSWORD,,}" == "true" ]; then
        echo "**** Impossible to use MySQL server because of unknown Zabbix user and random 'root' password"
        exit 1
    fi

    if [ ! -n "${MYSQL_USER}" ] && [ ! -n "${MYSQL_ROOT_PASSWORD}" ] && [ "${MYSQL_ALLOW_EMPTY_PASSWORD,,}" != "true" ]; then
        echo "*** Impossible to use MySQL server because 'root' password is not defined and it is not empty"
        exit 1
    fi

    if [ "${MYSQL_ALLOW_EMPTY_PASSWORD,,}" == "true" ] || [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
        USE_DB_ROOT_USER=true
        DB_SERVER_ROOT_USER=${MYSQL_ROOT_USER:-"root"}
        DB_SERVER_ROOT_PASS=${MYSQL_ROOT_PASSWORD:-""}
    fi

    [ -n "${MYSQL_USER}" ] && [ "${USE_DB_ROOT_USER}" == "true" ] && CREATE_DB_USER=true

    # If root password is not specified use provided credentials
    DB_SERVER_ROOT_USER=${DB_SERVER_ROOT_USER:-${MYSQL_USER}}
    [ "${MYSQL_ALLOW_EMPTY_PASSWORD,,}" == "true" ] || DB_SERVER_ROOT_PASS=${DB_SERVER_ROOT_PASS:-${MYSQL_PASSWORD}}
    DB_SERVER_USER=${MYSQL_USER:-"root"}
    DB_SERVER_PASS=${MYSQL_PASSWORD:-"ysyh!9Sky"}

    DB_SERVER_DBNAME=${MYSQL_DATABASE:-"open_paas"}

    if [ ! -n "${DB_SERVER_SOCKET}" ]; then
        mysql_connect_args="-h ${DB_SERVER_HOST} -P ${DB_SERVER_PORT}"
    else
        mysql_connect_args="-S ${DB_SERVER_SOCKET}"
    fi
}

db_tls_params() {
    local result=""

    if [ "${DB_ENCRYPTION,,}" == "true" ]; then
        result="--ssl-mode=required"

        if [ -n "${DB_CA_FILE}" ]; then
            result="${result} --ssl-ca=${DB_CA_FILE}"
        fi

        if [ -n "${DB_KEY_FILE}" ]; then
            result="${result} --ssl-key=${DB_KEY_FILE}"
        fi

        if [ -n "${DB_CERT_FILE}" ]; then
            result="${result} --ssl-cert=${DB_CERT_FILE}"
        fi
    fi

    echo $result
}

check_db_connect_mysql() {
    echo "********************"
    if [ ! -n "${DB_SERVER_SOCKET}" ]; then
        echo "* DB_SERVER_HOST: ${DB_SERVER_HOST}"
        echo "* DB_SERVER_PORT: ${DB_SERVER_PORT}"
    else
        echo "* DB_SERVER_SOCKET: ${DB_SERVER_SOCKET}"
    fi
    echo "* DB_SERVER_DBNAME: ${DB_SERVER_DBNAME}"
    if [ "${DEBUG_MODE,,}" == "true" ]; then
        if [ "${USE_DB_ROOT_USER}" == "true" ]; then
            echo "* DB_SERVER_ROOT_USER: ${DB_SERVER_ROOT_USER}"
            echo "* DB_SERVER_ROOT_PASS: ${DB_SERVER_ROOT_PASS}"
        fi
        echo "* DB_SERVER_USER: ${DB_SERVER_USER}"
        echo "* DB_SERVER_PASS: ${DB_SERVER_PASS}"
    fi
    echo "********************"

    WAIT_TIMEOUT=5

    ssl_opts="$(db_tls_params)"

    export MYSQL_PWD="${DB_SERVER_ROOT_PASS}"

    while [ ! "$(mysqladmin ping $mysql_connect_args -u ${DB_SERVER_ROOT_USER} \
                --silent --connect_timeout=10 $ssl_opts)" ]; do
        echo "**** MySQL server is not available. Waiting $WAIT_TIMEOUT seconds..."
        sleep $WAIT_TIMEOUT
    done

    unset MYSQL_PWD
}

mysql_query() {
    query=$1
    local result=""

    ssl_opts="$(db_tls_params)"

    export MYSQL_PWD="${DB_SERVER_ROOT_PASS}"

    result=$(mysql --silent --skip-column-names $mysql_connect_args \
             -u ${DB_SERVER_ROOT_USER} -e "$query" $ssl_opts)

    unset MYSQL_PWD

    echo $result
}

exec_sql_file() {
    sql_script=$1

    local command="cat"

    ssl_opts="$(db_tls_params)"

    export MYSQL_PWD="${DB_SERVER_ROOT_PASS}"

    if [ "${sql_script: -3}" == ".gz" ]; then
        command="zcat"
    fi

    $command "$sql_script" | mysql --silent --skip-column-names \
            --default-character-set=${DB_CHARACTER_SET} \
            $mysql_connect_args \
            -u ${DB_SERVER_ROOT_USER} $ssl_opts  \
            ${DB_SERVER_DBNAME} 1>/dev/null

    unset MYSQL_PWD
}

create_db_user_mysql() {
    [ "${CREATE_DB_USER}" == "true" ] || return

    echo "** Creating '${DB_SERVER_USER}' user in MySQL database"

    USER_EXISTS=$(mysql_query "SELECT 1 FROM mysql.user WHERE user = '${DB_SERVER_USER}' AND host = '%'")

    if [ -z "$USER_EXISTS" ]; then
        mysql_query "CREATE USER '${DB_SERVER_USER}'@'%' IDENTIFIED BY '${DB_SERVER_PASS}'" 1>/dev/null
    else
        mysql_query "ALTER USER ${DB_SERVER_USER} IDENTIFIED BY '${DB_SERVER_PASS}';" 1>/dev/null
    fi

    mysql_query "GRANT ALL PRIVILEGES ON $DB_SERVER_DBNAME. * TO '${DB_SERVER_USER}'@'%'" 1>/dev/null
}

create_db_database_mysql() {
    DB_EXISTS=$(mysql_query "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_SERVER_DBNAME}'")

    if [ -z ${DB_EXISTS} ]; then
        echo "** Database '${DB_SERVER_DBNAME}' does not exist. Creating..."
        mysql_query "CREATE DATABASE ${DB_SERVER_DBNAME} CHARACTER SET ${DB_CHARACTER_SET} COLLATE ${DB_CHARACTER_COLLATE}" 1>/dev/null
        # better solution?
        mysql_query "GRANT ALL PRIVILEGES ON $DB_SERVER_DBNAME. * TO '${DB_SERVER_USER}'@'%'" 1>/dev/null
    else
        echo "** Database '${DB_SERVER_DBNAME}' already exists. Please be careful with database COLLATE!"
    fi
}


prepare_db() {
    echo "** Preparing database"

    check_variables_mysql
    check_db_connect_mysql
    create_db_user_mysql
    create_db_database_mysql
}

update_config() {
   sed -i "s|NAME[[:space:]]*':[[:space:]]*'[^']*|NAME': '$DB_SERVER_DBNAME|g" $PAAS_PATH/paas/conf/settings_production.py
   sed -i "s|USER[[:space:]]*':[[:space:]]*'[^']*'|USER': '$DB_SERVER_USER'|g" $PAAS_PATH/paas/conf/settings_production.py
   sed -i "s|PASSWORD[[:space:]]*':[[:space:]]*'[^']*'|PASSWORD': '$DB_SERVER_PASS'|g" $PAAS_PATH/paas/conf/settings_production.py
   sed -i "s|HOST[[:space:]]*':[[:space:]]*'[^']*'|HOST': '$DB_SERVER_HOST'|g" $PAAS_PATH/paas/conf/settings_production.py
   sed -i "s|PORT[[:space:]]*':[[:space:]]*'[^']*'|PORT': '$DB_SERVER_PORT'|g" $PAAS_PATH/paas/conf/settings_production.py
   sed -i "s|PAAS_DOMAIN[[:space:]]*=[[:space:]]*'[^']*'|PAAS_DOMAIN = '$PAASDOMAIN'|g" $PAAS_PATH/paas/conf/settings_production.py
   sed -i "s|BK_COOKIE_DOMAIN[[:space:]]*=[[:space:]]*'[^']*'|BK_COOKIE_DOMAIN = '$COOKIEDOMAIN'|g" $PAAS_PATH/paas/conf/settings_production.py
   sed -i "s|SECRET_KEY[[:space:]]*=[[:space:]]*'[^']*'|SECRET_KEY = '$SECRETKEY'|g" $PAAS_PATH/paas/conf/settings_production.py
   sed -i "s|ESB_TOKEN[[:space:]]*=[[:space:]]*'[^']*'|ESB_TOKEN = '$ESBTOKEN'|g" $PAAS_PATH/paas/conf/settings_production.py

   sed -i "s|NAME[[:space:]]*':[[:space:]]*'[^']*|NAME': '$DB_SERVER_DBNAME|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|USER[[:space:]]*':[[:space:]]*'[^']*'|USER': '$DB_SERVER_USER'|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|PASSWORD[[:space:]]*':[[:space:]]*'[^']*'|PASSWORD': '$DB_SERVER_PASS'|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|HOST[[:space:]]*':[[:space:]]*'[^']*'|HOST': '$DB_SERVER_HOST'|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|PORT[[:space:]]*':[[:space:]]*'[^']*'|PORT': '$DB_SERVER_PORT'|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|USERNAME[[:space:]]*=[[:space:]]*'[^']*'|USERNAME = '$PAASUSER'|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|PASSWORD[[:space:]]*=[[:space:]]*'[^']*'|PASSWORD = '$PAASPWD'|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|BK_COOKIE_DOMAIN[[:space:]]*=[[:space:]]*'[^']*'|BK_COOKIE_DOMAIN = '$COOKIEDOMAIN'|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|SECRET_KEY[[:space:]]*=[[:space:]]*'[^']*'|SECRET_KEY = '$SECRETKEY'|g" $PAAS_PATH/login/conf/settings_production.py
   sed -i "s|ESB_TOKEN[[:space:]]*=[[:space:]]*'[^']*'|ESB_TOKEN = '$ESBTOKEN'|g" $PAAS_PATH/login/conf/settings_production.py

   sed -i "s|NAME[[:space:]]*':[[:space:]]*'[^']*|NAME': '$DB_SERVER_DBNAME|g" $PAAS_PATH/appengine/controller/settings.py
   sed -i "s|USER[[:space:]]*':[[:space:]]*'[^']*'|USER': '$DB_SERVER_USER'|g" $PAAS_PATH/appengine/controller/settings.py
   sed -i "s|PASSWORD[[:space:]]*':[[:space:]]*'[^']*'|PASSWORD': '$DB_SERVER_PASS'|g" $PAAS_PATH/appengine/controller/settings.py
   sed -i "s|HOST[[:space:]]*':[[:space:]]*'[^']*'|HOST': '$DB_SERVER_HOST'|g" $PAAS_PATH/appengine/controller/settings.py
   sed -i "s|PORT[[:space:]]*':[[:space:]]*'[^']*'|PORT': '$DB_SERVER_PORT'|g" $PAAS_PATH/appengine/controller/settings.py
   sed -i "s|SECRET_KEY[[:space:]]*=[[:space:]]*'[^']*'|SECRET_KEY = '$SECRETKEY'|g" $PAAS_PATH/appengine/controller/settings.py

   sed -i "s|NAME[[:space:]]*':[[:space:]]*'[^']*|NAME': '$DB_SERVER_DBNAME|g" $PAAS_PATH/esb/configs/default.py
   sed -i "s|USER[[:space:]]*':[[:space:]]*'[^']*'|USER': '$DB_SERVER_USER'|g" $PAAS_PATH/esb/configs/default.py
   sed -i "s|PASSWORD[[:space:]]*':[[:space:]]*'[^']*'|PASSWORD': '$DB_SERVER_PASS'|g" $PAAS_PATH/esb/configs/default.py
   sed -i "s|HOST[[:space:]]*':[[:space:]]*'[^']*'|HOST': '$DB_SERVER_HOST'|g" $PAAS_PATH/esb/configs/default.py
   sed -i "s|PORT[[:space:]]*':[[:space:]]*'[^']*'|PORT': '$DB_SERVER_PORT'|g" $PAAS_PATH/esb/configs/default.py
   sed -i "s|ESB_TOKEN[[:space:]]*=[[:space:]]*'[^']*'|ESB_TOKEN = '$ESBTOKEN'|g" $PAAS_PATH/esb/configs/default.py
   
}
