#!/bin/bash
# 所有脚本分为3个:
# monitor.sh: 用于任务监控,可以入到 crontab里
#    start.sh: 存储启动主进程启动的命令
#    xxxxx.sh/py/jar: 主进程程序
cur_path=$(cd $(dirname $0) && pwd)

# 此参数为必须
# 此参数为必须
# 此参数为必须
# 监控脚本(monitor.sh)通过该参数从该脚本中获取到主程序名从而监控主程序
# 注意不要有空格,不要有引号
process_file=load_file2ch.sh

cd ${cur_path}

bash ${cur_path}/${process_file}
