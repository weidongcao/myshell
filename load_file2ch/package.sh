#!/bin/bash
# 打包脚本
set -e

rm -rf load_file2ch.sh.tar.gz

tar -czhvf load_file2ch.sh.tar.gz \
    --exclude-vcs \
    --exclude-vcs-ignores \
    ../load_file2ch.sh/README.org \
    ../load_file2ch.sh/commons.sh \
    ../load_file2ch.sh/monitor.sh \
    ../load_file2ch.sh/conf.properties \
    ../load_file2ch.sh/start.sh \
    ../load_file2ch.sh/load_file2ch.sh.sh

echo "打包成功"
