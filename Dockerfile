#############################
#     设置公共的变量         #
#############################
ARG BASE_IMAGE_TAG=latest
FROM danxiaonuo/cmdb-base:${BASE_IMAGE_TAG}

# 作者描述信息
MAINTAINER danxiaonuo
# 时区设置
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
# 语言设置
ARG LANG=zh_CN.UTF-8
ENV LANG=$LANG

# 镜像变量
ARG DOCKER_IMAGE=danxiaonuo/cmdb-base
ENV DOCKER_IMAGE=$DOCKER_IMAGE
ARG DOCKER_IMAGE_OS=cmdb-base
ENV DOCKER_IMAGE_OS=$DOCKER_IMAGE_OS
ARG DOCKER_IMAGE_TAG=latest
ENV DOCKER_IMAGE_TAG=$DOCKER_IMAGE_TAG

# 环境设置
ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND=$DEBIAN_FRONTEND

# 仓库信息
ARG VERSION=master
ENV VERSION=$VERSION
ARG SOURCES=https://github.com/TencentBlueKing/legacy-bk-paas
ENV SOURCES=$SOURCES
ARG SOURCES_DIR=/tmp/legacy-bk-paas
ENV SOURCES_DIR=$SOURCES_DIR

# ***** 克隆源码 *****
RUN set -eux && \
   # 克隆源码
   git clone --depth=1 -b $VERSION --progress ${SOURCES} ${SOURCES_DIR} && \
   mkdir -pv /data && cp -rfp ${SOURCES_DIR}/paas-ce/paas /data/ && \
   cp -rfp /data/paas/paas/conf/settings_production.py.sample /data/paas/paas/conf/settings_production.py && \
   cp -rfp /data/paas/login/conf/settings_production.py.sample /data/paas/login/conf/settings_production.py && \
   cp -rfp /tmp/paas/esb/configs/default_template.py /tmp/paas/esb/configs/default.py && \
