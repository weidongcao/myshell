#!/bin/bash
# 打包一键部署脚本
set -e

rm -rf fast_deploy.tar.gz

tar -czhvf fast_deploy.tar.gz \
    --exclude-vcs \
    --exclude-vcs-ignores \
    ../fast_deploy/README.org \
    ../fast_deploy/commons.sh \
    ../fast_deploy/conf.properties \
    ../fast_deploy/start.sh \
    ../fast_deploy/fast_deploy.sh

echo "打包成功"
