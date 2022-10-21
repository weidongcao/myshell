#!/bin/bash
# 监控服务是否启动
# 如果没有启动的话启动
# 使用的时候可以直接执行,或者加入crontab,例:
# * * * * * bash /data/module_name/monitor.sh
# 
# 修改的话该脚本不需要修改,只需要改start.sh即可:
# 
# 一般程序会用3个脚本:
# 1. 主程序脚本(load_file2ch.sh/xxx.py等)
# 2. start.sh脚本(用于主程序有很多参数传递,以防记不住)
# 3. 监控脚本(monitor.sh),即当前
# 
# 用于脚本调试
#set -e
#set -x
################################## 基础必须参数 #################################
# parameters
# 当前路径
cur_dir=$( cd $(dirname $0); pwd )
# 当前时间
cur_date=$(date "+%Y%m%d")
# 当前脚本名
file_name="${0##*/}"
# 脚本主线程PID作为数据生成目录
main_pid="$$"
# 数据目录
data_dir="${cur_dir}/data"
# 日志目录
log_dir="${cur_dir}/logs"
# 日志名称
log_file=${log_dir}/${file_name%.*}.log

# 如果数据目录,日志目录不存在则创建
[[ ! -d ${log_dir} ]] && mkdir -p ${log_dir}
[[ ! -d ${data_dir} ]] && mkdir -p ${data_dir}

# 加载公共方法
################################# 加载公共方法 ##################################
[[ -f ${cur_dir}/commons.sh ]] && common_file="${cur_dir}/commons.sh"
[[ -f ${cur_dir%/*}/commons/commons.sh ]] && common_file="${cur_dir%/*}/commons/commons.sh"

if [[ -f ${cur_dir}/commons.sh ]] ; then
    source ${common_file}
    logger "common function init success"
else
    echo "not found commons.sh in cur directory and parent directory, load commons.sh fail, I will exit"
    exit -1
fi

################################## 初始化变量 ##################################
# 启动脚本
start_file=start.sh
# 当前脚本名
file_name="${0##*/}"
# 动作类型(start,stop,restart)
action=${1}
action=${action:=start}


# 获取主进程脚本名,通过该脚本名判断进程存在
# 该变量为主程序文件名
# 通过该变量判断主程序是否不在运行
# 如果主程序挂了的话也通过该变量启动起来
# start.sh中必须有process_file=不带路径的主脚本名
file_list=($(ls ${cur_dir}))
content="$(cat ${cur_dir}/${start_file})"
for pf in ${file_list[@]}; do
    flag="process_file=${pf}"
    #logger $([[ -f ${cur_dir}/${pf} ]] && echo "file=true" || echo "file=false") 
    #logger $([[ "${content//${flag}/}" != "${content}" ]] && echo "contain=true" || echo "contain=false")
    if [[ -f ${cur_dir}/${pf} ]] && [[ "${content//${flag}/}" != "${content}" ]];then
        process_file=${pf}
        break
    fi
done
logger "main process file name is:--> ${process_file}"

# 实际要执行的命令:
# 需要跑后台
# 需要把标准错误输出重定向到标准输出
# 需要把标准输出重定向到空,以防止时间外了nohup.out文件太大
exec_cmd="bash ${cur_dir}/${start_file}"
exec_cmd="nohup ${exec_cmd} 1>${cur_dir}/nohup.out 2>&1 &"

# 一个小时清一次nohup.out
if [[ $(( RANDOM % 60 )) -eq 0 ]]; then
    cat /dev/null > ${cur_dir}/nohup.out
fi

# 判断主进程是否存在
pids=$(ps -ef | grep ${process_file} | grep -v "grep" | grep -v "vim" | sed 's/^[ ]*//g' | sed 's/[ ][ ]*/ /g' | awk '{print $2}')

pids=(${pids})

# 如果进程存在,但是日志文件已经超过10分钟没有更新了则重启
# 如果参数为stop,或者restart则先杀掉进程
if [[ ${#pids[@]} -ne 0 ]]; then
    logger "process(${process_file}) is already running, pid is: ${pids[*]}"

    # 如果进程存在,但是日志文件已经超过10分钟没有更新了则重启
    process_log_file_name=${process_file%.*}.log
    process_log_file=$(find ${log_dir} -name "${process_log_file_name}" -mmin +10)
    if [[ -f "${process_log_file}" ]] && [[ ! "${action}" == "stop" ]]; then
        logger "process(${process_file}) service has no response for 10 minutes, action switch to restart" "WARNING"
        action="restart"
    fi

    # 如果参数为stop,或者restart则先杀掉进程
    if [[ "${action}" == "stop" ]] || [[ "${action}" == "restart" ]]; then
        if [[ "${action}" == "stop" ]]; then
            logger "I will stop service"
        elif [[ "${action}" == "restart" ]]; then
            logger "I will stop service"
        fi

        # 先杀掉进程
        for p in ${pids[@]};do
            kill -9 ${p}
            logger "killed process: ${p}"
        done 
    fi
else
	logger "process(${process_file}) didn't start yet"
fi

# 判断是否需要启动主进程
# 如果进程不存在则启动
# 如果参数为restart则启动
if [[ "${action}" != "stop" ]] && [[ "${action}" != "status" ]]; then
	if [[ ${#pids[@]} -eq 0 ]] || [[ "${action}" == "restart" ]]; then
		logger "I will start service ${process_file}"
		eval "${exec_cmd}"
		logger "process(${process_file}) is started, status: $?, pid is: $$"
	fi
fi
