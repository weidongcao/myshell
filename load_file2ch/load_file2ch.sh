#!/bin/bash
############################# 打印变量值,调试时打开 ############################
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
# 配置文件名
conf_file=conf.properties

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

# 除了配置文件,再给一个默认参数
get_conf ${cur_dir}/${conf_file}

data_dir="${conf_map['data.dir']:=${cur_dir}/data}"
# ClickHouse-Server所在服务器
host="${conf_map['db.ch.host']:="127.0.0.1"}"
# ClickHouse端口
port="${conf_map['db.ch.port']:="9000"}"
# ClickHouse用户名
username="${conf_map['db.ch.user']:="wedo"}"
# ClickHouse密码
password="${conf_map['db.ch.password']:="123123"}"
# DNS解析日志导入的数据库表
tablename="${conf_map["ch.table.name"]:="dns_logs"}"
# 数据入库频率（分钟）
minutes_ago=${conf_map["import.minutes.get"]:=-5}
# 最大线程数
thread_num=${conf_map["import.thread.num"]:=5}
# 一次最多同时导入多少个数据文件
file_max_import_num=${conf_map["import.max.file.num"]:=5}
# 文件匹配模式
file_pattern="*.gz"
#字段个数
columns=(${conf_map["ch.table.columns"]:="ip domain ctime a_record rcode qtype cname aaaa_record business_ip"})
# 数据文件格式(Windows格式的换行还是Linux的换行)
#CRLF="Linux"
CRLF="${conf_map["file.crlf"]:="Linux"}"
is_loop=true
# 错误目录
error_dir="${cur_dir}/error"
[[ ! -d ${error_dir} ]] && mkdir -p ${error_dir}

# 程序唯一标识

# 定义一个字典,这个字典存放IP地址(在DNS数据文件名中体现)到网络类型(手机,固网,其他)的映射
declare -A ip2usertype

# 请自行根据自己项目的情况配置IP地址到网络类型的映射
# 如果不需要配置usertype,直接把字典清空即可
# 即把下面的配置注释掉
net_list=(   ${conf_map["business.ip.to.user.type.net"]}   )
mobile_list=(${conf_map["business.ip.to.user.type.mobile"]})
other_list=( ${conf_map["business.ip.to.user.type.other"]} )

for eee in ${net_list[@]}   ; do ip2usertype["${eee}"]="固网" ; done;
for eee in ${mobile_list[@]}; do ip2usertype["${eee}"]="手机" ; done;
for eee in ${other_list[@]} ; do ip2usertype["${eee}"]="其他" ; done;

cmd_template="timeout 600 zcat {file_list} | awk -v FS='|' -v OFS='|' -v RS='{CRLF}' '{if(NF == {column_count}) print \$0{user_type}}' | clickhouse-client --host={host} --port={port} --user={username} --password={password} --format_csv_delimiter='|' --date_time_input_format=best_effort --query='INSERT INTO {tablename}({columns}) FORMAT CSV' --max_partitions_per_insert_block=8192 >> {log_file} 2>&1"

# 如果不需要配置的话,请把上面的配置注释掉,
# 将ip2usertype清空, 程序会自动转为匹配所有
if [[ ${#ip2usertype[@]} -eq 0 ]]; then
	ip2usertype["0.0.0.0"]=""
fi

################################## 解析命令行传的参数 ##################################
# getopt指定命令行可以给脚本传哪些参数
# -a 为短选项(不需要值) ,这里没有定义
# -o 为短选项(需要值), 这里定义了-h, -p, -u, -P等等
# --long 为长选项需要值, 这里定义了--host, --port, --username, --password等等,
ARGS=$(getopt -a -o h:p:u:P:t:m:d:n:l: --long host:,port:,username:,password:,tablename:,minutes:,data_dir:,thread_num:,file_max_import_num:,file_min_size:,loop:,help -- "$@")

# 重排选项
if [ $? != 0 ]; then
    echo "Terminating..."
    exit 1
fi

eval set -- "${ARGS}"

# 解析命令行参数
while :; do
    case "$1" in
    -h | --host)
        host=${2}
        shift
        ;;
    -p | --port)
        port=${2}
        shift
        ;;
    -u | --username)
        username=${2}
        shift
        ;;
    -P | --password)
        password=${2}
        shift
        ;;
    -t | --tablename)
        #tablename=${2:-"src.wedotest"}
        tablename=${2}
        shift
        ;;
    -m | --minutes)
        minutes_ago=${2}
        shift
        ;;
    -n | --thread_num)
        thread_num=${2}
        shift
        ;;
    --file_max_import_num)
        file_max_import_num=${2}
        shift
        ;;
    -l | --loop)
        is_loop=${2}
        shift
        ;;
    -d | --data_dir)
        data_dir=${2}
        shift
        ;;
    --help)
        usage
        ;;
    --)
        shift
        break
        ;;
    *)
        logger "$1"
        logger "Internal error!"
        exit 1
        ;;
    esac
    shift
done
cmd1=${cmd_template}
[[ "${CRLF,,}" == "linux" ]] && cmd1=${cmd_template//\{CRLF\}/\\n} || cmd1=${cmd_template//\{CRLF\}/\\r?\\n}
cmd1=${cmd1//\{host\}/${host}}
cmd1=${cmd1//\{port\}/${port}}
cmd1=${cmd1//\{username\}/${username}}
cmd1=${cmd1//\{password\}/${password}}
cmd1=${cmd1//\{tablename\}/${tablename}}

cmd1=${cmd1//\{column_count\}/${#columns[@]}}

logger "ClickHouse host: ${host}"
logger "ClickHouse port: ${port}"
logger "ClickHouse username: ${username}"
logger "ClickHouse password: *********"
logger "ClickHouse tablename: ${tablename}"
logger "ClickHouse import data from ${minutes_ago} minutes"
logger "thread_num : ${thread_num}"
logger "data path: ${data_dir}"

################################## 初始化多线程 ##################################
temp_fifofile="/tmp/$$.fifo"
mkfifo $temp_fifofile

# 将fd6指向fifo类型
# 使文件描述符为非阻塞式
exec 6<>$temp_fifofile
rm $temp_fifofile

#根据线程总数量设置令牌个数
for ((i = 0; i < thread_num; i++)); do
    echo
done >&6
logger "multiple thread init finish, thread number: ${thread_num}"

# 创建子线程执行导入
function exec_cmd() {
    #logger "start import file list: \n $(echo $1 | sed 's/ /\n/g')"
    #user_type="固网"
	if [[ -n "$2" ]]; then
		user_type=${ip2usertype[$2]}
	fi
    lt=($1)
    #printf '%s\n' "${lt[@]}" >> ${log_file}
	import_cmd=${cmd1//\{file_list\}/${lt[*]}}
	import_cmd=${import_cmd//\{log_file\}/${log_file}}
	if [[ -n "${user_type}" ]]; then
		import_cmd=${import_cmd//\{user_type\}/, \"${user_type}\"} 
		import_cmd=${import_cmd//\{columns\}/$(echo "${columns[*]} user_type" | tr ' ' ', ')}
	else
		import_cmd=${import_cmd//\{user_type\}/}
		import_cmd=${import_cmd//\{columns\}/$(echo ${columns[*]} | tr ' ' ', ')}
	fi

    # 导入ClickHouse命令模板

    # 该线程导入开始时间，用以记录线程执行时间
    start_time=$(get_timestamp)

    # 执行导入命令
    eval "${import_cmd}"
    #echo "${import_cmd}"
    result_status=$?

    #result_status=$((result_status + $?))

    # 判断是否导入成功，导入成功则删除数据文件,不成功仅提示错误
    if [ ${result_status} -eq 0 ]; then
        # 记录导入命令执行时间
        import_time=$(get_timestamp)
        #logger "success, elapsed time: $(printf '%5d' $((import_time - start_time)))ms, count = $((import_data_count / 10000))W file start: ${lt##*/}"
        logger "import success, time: $(printf '%6d' $((import_time - start_time)))ms; files: (${lt[*]//${data_dir}\//})"
        #logger "import command file data to ClickHouse command:-->  ${import_cmd}"
        if [[ $((RANDOM % 100)) -eq 0 ]]; then
            logger "execute command:-->  ${import_cmd}"
        fi

        # 删除数据文件命令模板
        rm_cmd="rm -f  ${lt[*]}"

        # 删除导入成功的数据文件
        eval "${rm_cmd}"

        # 记录删除命令执行时间
        #mv_time=$(get_timestamp)
        #logger "delete file: time consume: $((mv_time - import_time)), cmd: ${rm_cmd}"
    else
        #mv ${lt[*]} ${error_dir}
        if [[ ${result_status} -eq 124 ]]; then
            # 导入失败，提示错误
            logger "DNS日志导入ClickHouse失败(timeout),命令:${import_cmd}"
        else
            # 导入失败，提示错误
            logger "DNS日志导入ClickHouse失败,命令:${import_cmd}"
        fi
        sleep 10
        #exit -1
    fi

    # 当进程结束以后返还令牌
    echo "" >&6
    #logger "finish import data to clickhouse"
}
############################### 数据导入ClickHouse ###############################

# 导入数据到ClickHouse,逻辑如下:
# 1. while循环判断导入程序是否需要结束, 程序结束的判断标准是:
#       1. 数据目录下是否还有数据文件
#       2. 目前是死循环
# 2. 通过find命令获取数据目录下指定时间段的数据文件,循环导入所有文件
#       1. 读取1个线程令牌以创建1个子线程,如果没有令牌等待
#       2. 执行导入命令
#       3. 判断是否导入成功
#           1. 成功 --> 删除数据文件
#           2. 失败 --> 提示错误
# 4. 导入所有find出来的文件后,等待所有子线程执行完毕
# 5. 再次判断Java线程是否结束及数据目录下是否还有数据文件
# 6. 进行下一次循环
#
# 7. 关闭线程流及令牌
# 8. 删除数据目录

# 先统计数据目录下最近一段时间是否有数据文件
import_start_time=0
while true; do
	# 当前一次导入的最大文件个数
	# 加入这个参数主要是考虑到数据太多的时候,需要导入快些，数据文件较少的时候需要减少延迟
	# 历史数据文件太多，就需要一次导入的文件比较多，以提高导入效率
	# 实时数据对对实时性要求高些（如1分钟必须导完），就需要一次导入的文件少此，以减少延迟
	cur_file_max_import_num=${file_max_import_num}
	cur_thread_num=${thread_num}
	# 获取时间段内所有的日志文件
	all_file_num=0

	# 没有数据的业务服务器IP
	no_data_net_type_ip=()

	for ip_addr in ${!ip2usertype[@]};do

		# 获取新生成的日志文件列表
		# 如果ip值为0.0.0.0表示获取所有ip类型的文件, 
		# 如果不是,表示按ip导入数据
		find_start_time=$(get_timestamp)
		if [[ "${ip_addr}" == "0.0.0.0" ]]; then
			find_file_array=$(find ${data_dir} -name "*.gz" -mmin +0.1 -mmin ${minutes_ago} 2>/dev/null | sort)
		else
			find_file_array=$(find ${data_dir} -name "*$(convert_IP ${ip_addr})*.gz" -mmin +0.1 -mmin ${minutes_ago} 2>/dev/null | sort)
		fi
		#find_file_array=$(find ${data_dir} -name "*.gz" -mmin "${minutes_ago}" 2>/dev/null | awk -F "_" '{if(NF>3) {print $3,$0} else if(NF==3) {print $2,$0}}'  | sort | awk '{print $2}')

		# 将字符串转为shell数组
		find_file_array=(${find_file_array})

		# 数据文件数量
		file_num=${#find_file_array[@]}
		all_file_num=$((all_file_num + file_num))
		logger "all_file_num=${all_file_num}; ${ip_addr}=${file_num}" DEBUG

		# 判断文件列表是否为空
		if [[ ${file_num} -eq 0 ]]; then
			# 没有数据的net_type,统一打印日志,以避免日志太多
			no_data_net_type_ip[${#no_data_net_type_ip[@]}]="${ip_addr}"
		else

			# 数据文件少于30个的时候，一次少导些文件
			if [[ ${file_num} -le 30 ]]  && [[ ${file_max_import_num} -gt 2 ]]; then
				cur_file_max_import_num=2
			fi
			logger "find ${file_num} files(${ip_addr}) in ${data_dir} last $((0 - minutes_ago)) minutes, max file number import in once was set to ${cur_file_max_import_num}"
			

			# 需要导入的数据文件列表
			wait_import_file_array=()
			# 获取数据目录下最近多少分钟修改过的数据文件
			for data_file in ${find_file_array[@]}; do
				# 达到最大文件个数即开始入库
				if [[ ${#wait_import_file_array[@]} -ge ${cur_file_max_import_num} ]]; then
					# 获取1个令牌
					read -u6

					# 创建子线程执行导入
					{
						exec_cmd "${wait_import_file_array[*]}" "${ip_addr}"
					} &

					# 重置数组
					wait_import_file_array=()
				fi

				wait_import_file_array[${#wait_import_file_array[@]}]=${data_file}

				# gz文件完整性检查
				#logger "start check gzip is complateness"
				#gzip -t ${data_file} 2>/dev/null
				#if [[ $? -eq 0 ]];then
				#    wait_import_file_array[${#wait_import_file_array[@]}]=${data_file}
				#    logger "add file to wait import array: ${data_file}"
				#else
				#    logger "skip import, file not complateness, name = ${file##*/}"
				#fi
			done
			if [[ ${#wait_import_file_array[@]} -gt 0 ]]; then
				# 获取1个令牌
				read -u6

				# 创建子线程执行导入
				{
					exec_cmd "${wait_import_file_array[*]}" "${ip_addr}"
				} &
				#}

				# 重置数组
				wait_import_file_array=()
			fi
		fi

		wait
	done


	# 导入完毕,处理导入结果(导入了多少数据文件,累计耗时,是否超过入库频率)
	if [[ ${all_file_num} -gt 0 ]]; then
		find_finish_time=$(get_timestamp)
		time_consume=$(((find_finish_time - find_start_time) / 1000))
		# 没有数据的net_type,统一打印日志,以避免日志太多
		if [[ ${#no_data_net_type_ip[@]} -gt 0 ]]; then
			logger "${data_dir} [${no_data_net_type_ip[*]}] no files last $((0 - minutes_ago)) minutes, skip.."
			no_data_net_type_ip=()
		else
			logger "finish import all find ${all_file_num:=0} files(in last $((0 - minutes_ago)) minutes) elapsed time: ${time_consume} Seconds"
		fi
		if [[ $((-minutes_ago * 60)) -lt ${time_consume} ]]; then
			logger "time-consuming(${time_consume} Seconds) is more than find time($((0 - minutes_ago)) Minutes)!!! data overstock!!!" "WARNING"
			logger "time-consuming(${time_consume} Seconds) is more than find time($((0 - minutes_ago)) Minutes)!!! data overstock!!!" "WARNING"
			logger "time-consuming(${time_consume} Seconds) is more than find time($((0 - minutes_ago)) Minutes)!!! data overstock!!!" "WARNING"
		fi
	else
		logger "${data_dir} find ${all_file_num} files last $((0 - minutes_ago)) minutes, I will sleep 5 seconds"

		# 如果没有数据文件进入，休眠5秒
		sleep 5

		# 如果开始导入时间为0，则设置当前时间为导入开始时间
		if [[ $import_start_time -eq 0 ]]; then
			import_start_time=$(get_timestamp)
		fi
	fi

	logger " "
	#done
	if [[ "${is_loop}" != "true" ]]; then
		break
	fi
done
import_end_time=$(get_timestamp)
echo "import time comsume: $((import_end_time - import_start_time))"

# 等待所有子线程结束
wait

# 删除线程流及令牌
exec 6>&-

# 删除数据目录
#rm -rf "${data_dir}"
#logger "finish, I will delete data directory: ${data_dir}"

logger " --> over"
