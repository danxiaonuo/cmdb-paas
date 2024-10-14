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

# 安装依赖包
ARG PKG_DEPS="\
    mysql-client \
    libmysqlclient21"
    
# ***** 安装依赖 *****
RUN --mount=type=cache,target=/var/lib/apt/,sharing=locked \
   set -eux && \
   # 更新源地址
   sed -i s@http://*.*ubuntu.com@https://mirrors.aliyun.com@g /etc/apt/sources.list && \
   sed -i 's?# deb-src?deb-src?g' /etc/apt/sources.list && \
   # 解决证书认证失败问题
   touch /etc/apt/apt.conf.d/99verify-peer.conf && echo >>/etc/apt/apt.conf.d/99verify-peer.conf "Acquire { https::Verify-Peer false }" && \
   # 更新系统软件
   DEBIAN_FRONTEND=noninteractive apt-get update -qqy && apt-get upgrade -qqy && \
   # 安装依赖包
   DEBIAN_FRONTEND=noninteractive apt-get install -qqy --no-install-recommends $PKG_DEPS --option=Dpkg::Options::=--force-confdef && \
   DEBIAN_FRONTEND=noninteractive apt-get -qqy --no-install-recommends autoremove --purge && \
   DEBIAN_FRONTEND=noninteractive apt-get -qqy --no-install-recommends autoclean && \
   rm -rf /var/lib/apt/lists/* && \
   # 克隆源码
   git clone --depth=1 -b $VERSION --progress ${SOURCES} ${SOURCES_DIR} && \
   mkdir -pv /data && cp -rfp ${SOURCES_DIR}/paas-ce/paas /data/ && \
   mkdir -pv /data/paas/logs && \
   cp -rfp /data/paas/paas/conf/settings_production.py.sample /data/paas/paas/conf/settings_production.py && \
   cp -rfp /data/paas/login/conf/settings_production.py.sample /data/paas/login/conf/settings_production.py && \
   cp -rfp /data/paas/esb/configs/default_template.py /data/paas/esb/configs/default.py && \
   sed -i '/uWSGI/d' /data/paas/*/requirements.txt && \
   cd /data/paas/paas && pip install -r requirements.txt && \
   cd /data/paas/login && pip install -r requirements.txt && \
   cd /data/paas/appengine && pip install -r requirements.txt && \
   cd /data/paas/esb && pip install -r requirements.txt

# 拷贝文件
COPY ["./docker-entrypoint.sh", "/usr/bin/"]
COPY ["./conf/supervisor", "/etc/supervisor"]

# ***** 目录授权 *****
RUN set -eux && \
    cp -rf /root/.oh-my-zsh /data/paas/.oh-my-zsh && \
    cp -rf /root/.zshrc /data/paas/.zshrc && \
    sed -i '5s#/root/.oh-my-zsh#/data/paas/.oh-my-zsh#' /data/paas/.zshrc && \
    chmod a+x /usr/bin/docker-entrypoint.sh && \
    chmod -R 775 /data && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# ***** 容器信号处理 *****
STOPSIGNAL SIGQUIT

# ***** 工作目录 *****
WORKDIR /data/paas

# ***** 挂载目录 *****
VOLUME ["/data/paas"]

# ***** 入口 *****
ENTRYPOINT ["docker-entrypoint.sh"]
