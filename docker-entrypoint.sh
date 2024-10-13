#!/bin/bash -e

# 检查mysql数据库变量
check_variables() {
    if [ ! -n "${DB_SERVER_SOCKET}" ]; then
        : ${DB_SERVER_HOST:="127.0.0.1"}
    else
        DB_SERVER_HOST="localhost"
    fi
    : ${DB_SERVER_PORT:="3306"}

    file_env MYSQL_USER
    file_env MYSQL_PASSWORD

    DB_SERVER_ZBX_USER=${MYSQL_USER:-"root"}
    DB_SERVER_ZBX_PASS=${MYSQL_PASSWORD:-"ysyh!9Sky"}

    DB_SERVER_DBNAME=${MYSQL_DATABASE:-"open_paas"}

    if [ ! -n "${DB_SERVER_SOCKET}" ]; then
        mysql_connect_args="-h ${DB_SERVER_HOST} -P ${DB_SERVER_PORT}"
    else
        mysql_connect_args="-S ${DB_SERVER_SOCKET}"
    fi
}
