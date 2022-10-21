#!/bin/bash
#############################     程序使用说明      ############################
# 请在修改该脚本之前一定要先看完该注释:
# 该文件(commons.sh)非常重要
# 该文件存放的是一些bash通用方法
# 主要包括以下方法:
# 1. 打印日志
# 2. 执行命令
# 3. 读取配置文件
# 
# 该通用代码文件一定要复制到与主程序在同级目录下使用,不然可能会出问题
# 调用commons.sh文件的命令:
#   source commons.sh
#
# 最好的方法是:
#	在主程序的同级目录下创建一个软链接
############################# 打印变量值,调试时打开 ############################
#set -x
#set -e
set -o pipefail

#############################     基础必须函数      ############################
# 定义Log日志级别对应的权重
# 当当前级别低于程序级别则不打印
# 当前时间
cur_date=$(date "+%Y%m%d")

# 日志的默认级别
log_level=INFO

# 定义日志级别的权重
# 只有大于程序日志级别的都会被打印
# 例如程序里定义了全局日志级别为WARN(警告)
# 则DEBUG, INFO都不会被打印
declare -A log_map_weight
log_map_weight["DEBUG"]=1
log_map_weight["INFO"]=2
log_map_weight["WARN"]=3
log_map_weight["ERROR"]=4

# 打印控制台时的颜色
declare -A log_map_color
# DEBUG为蓝色
log_map_color["DEBUG"]='\033[34m'
# INFO为白色
log_map_color["INFO"]='\033[37m'
# 警告为黄色
log_map_color["WARN"]='\033[1;33m'
# 错误为红色
log_map_color["ERROR"]='\033[1;31m'
# 颜色结束标识
log_map_color["END"]='\033[0m'
# 执行成功的为绿色
log_map_color["SUCCESS"]='\033[32m'

# 占位符
pad=$(printf '%0.1s' "-"{1..200})


# 获取时间戳
function get_timestamp(){
    echo $(($(date +%s%N) / 1000000))
}

function fmt_arr(){
	arr=${1:-""}
	separator=${2:-" "}
	echo $(echo "${arr}" | tr "${separator}" " " | tr -s " ")
}

# 打印日志
# 实现以下功能:
#	1. 以标准格式输出: 时间 [日志级别] 日志详情
#	2. 同时输出到stdout和文件
#	3. 输出到文件时日志文件名与程序文件名同名不同后缀,如在test.sh文件中调用,输出文件即为logs/test.log
#	4. 输出到文件时邮变量log_file参数控制,如果没有设置该变量,则不输出到文件
#	5. log_file变量请在脚本文件中设置,不要在commons.sh中设置,commons.sh尽量不涉及业务逻辑
#	6. 设置log_file变量把日志输出到同名脚本.log文件的代码如下:
#		#获取当前路径
#		cur_dir=$( cd $(dirname $0); pwd )
#		# 当前脚本文件名
#		file_name="${0##*/}"
#		# 日志文件所在目录(同级logs目录)
#		log_dir="${cur_dir}/logs"
#		# 获取程序文件名,并拼接日志文件路径
#		log_file=${log_dir}/${file_name%.*}.log
#		# 判断日志目录是否存在
#		[[ ! -d ${log_dir} ]] && mkdir -p ${log_dir}
#		这样,假如以上代码在test.sh中,日志文件会输出到:logs/test.log下
#	7. 日志文件按天分割以免文件过大
#	8. 对以前的日志文件进行压缩
function logger(){
	# 当前日期
	# 根据当前日期和当天日期判断是否是新的一天,
	# 是否需要将日志写入新的文件
	now_date=$(date "+%Y%m%d")

	# 当前日志级别
	# 根据当前日志级别和默认日志级别确定最终输出的日志级别
	# 如:
	#	当前日志级别没有设置,则使用默认日志级别
	#	如果当前日志级别设置了,就使用当前日志级别
	#	如果当前日志级别设置了,但是比默认日志级别低,则不打印
	cur_log_level=${2^^}
	cur_log_level=${cur_log_level:=${log_level}}
	
	# 当前日志级别对应的权重
	cur_level_num=${log_map_weight[${cur_log_level}]:=0}

	# 只有当前日志级别大于等于程序日志级别才打印日志
	# 例当前日志级别为DEBUG,
	# 程序日志级别为INFO
	# 则不打印
	if [[ ${cur_level_num} -ge ${log_map_weight[${log_level}]} ]]; then

		# 判断是否为新的一天
		# 日志则会追加到新的日志文件里
		if [[ ${cur_date} -ne ${now_date} ]];then
			old_log_file=${log_file}.${cur_date}
			# 如果为新的一天则将当前日志重命名为日志文件名.日期
			mv ${log_file} ${old_log_file}
			# 并对旧日志进行压缩
			tar -czf ${old_log_file}.tar.gz ${old_log_file}
			# 删除未压缩
			rm -f ${old_log_file}

			# 更新当天日期
			cur_date=${now_date}
		fi

		# 进程PID
		# 由于进程PID会变,此功能暂时不用
		thread_id=$(printf "thread-%-5d" $BASHPID)
		if [[ $$ -eq $BASHPID ]]; then
			thread_id="thread-main($$)"
		fi

		# 处理日志内容包含换行的情况
		# 临时重新定义元素分隔符为\n
		# 不然的话遇到空格和换行就是一个元素
		OLD_IFS=${IFS}
		IFS=$'\n'
		log_list=(${1})
		# 恢复系统默认的元素分隔符
		IFS=${OLD_IFS}

		# 如果日志内容为空,表示打印空行
		if [[ ${#log_list[@]} -eq 0 ]]; then
			log_list=('')
		fi

		for i in ${!log_list[@]}; do
			line="${log_list[i]}"

			# 根据关键字判断命令是否执行成功,从而改变终端的颜色
			# 默认不成功, 但是如果包含seccess succeed pass 成功 通过则认为成功
			# 但是如果日志级别是ERROR,或者WARN 则返回默认
			success_status=false
			if [[ ${cur_log_level} != "ERROR" ]] && [[ ${cur_log_level} != "WARN" ]]; then
				for ele in '[success]' '[succeed]'  '[pass]' '[成功]' '[通过]'; do
					if [[ "${line,,}" =~ "${ele}" ]]; then
						success_status=true
						break
					fi
				done
			fi

			# 如果标识成功,则终端显示为成功的颜色
			if [[ "${success_status}" == "true" ]]; then
				echo -e "${log_map_color[SUCCESS]}$(date "+%Y-%m-%d %H:%M:%S") [$(printf '%-5s' ${cur_log_level})] ${line}${log_map_color[END]}"
			else
				# 打印控制台
				echo -e "${log_map_color[${cur_log_level}]}$(date "+%Y-%m-%d %H:%M:%S") [$(printf '%-5s' ${cur_log_level})] ${line}${log_map_color[END]}"
			fi

			# 写入日志文件, 日志文件为与脚本名相同, 后缀为.log
			if [[ ${log_file} ]]; then
				echo "$(date "+%Y-%m-%d %H:%M:%S") [$(printf '%-5s' ${cur_log_level})] ${line}" >> ${log_file}
			fi
		done
	fi
}

# 执行命令,实现以下功能:
#	1. 打印该命令
#	2. 以日志的方式打印日志输出
#	3. 需要注意的是命令是有引号的话可能会出问题
#   4. sexec调oexec
#   5. oexec调myexec
function myexec(){

	# 对参数进行首尾去空白符
	# 命令功能描述
	# 对字符串进行首尾去除空白字符

	# [:space:]      :--> 正则表达式匹配所有空白符,包括tab和空格
	# [!strings]     :--> 正则表达式匹配所有非空白符
	# ${#%%strings*} :--> 移除字符串右边所有非空白字符及右边的空白符,即获取字符串开头的空白符
	# ${##strings}   :--> 移除一次匹配到的开头的空白符
	# :              :--> 内置用于代替临时变量
	# #              :--> 读取所有变量
	: "${*#"${*%%[![:space:]]*}"}"

	# [:space:]      :--> 正则表达式匹配所有空白符,包括tab和空格
	# [!strings]     :--> 正则表达式匹配所有非空白符
	# ${1##*strings} :--> 移除字符串左边所有非空白字符及左边的空白符,即获取字符串结尾的空白符
	# ${1#strings}   :--> 移除一次字符串结尾的空白符
	# :              :--> 内置用于代替临时变量
	: "${_%"${_##*[![:space:]]}"}"

	# _              :--> 临时变量,对应方面开头:
	cmd="${_:-""}"

	cmd_output="$(eval ${cmd} 2>&1)"

	exit_code=$?

	# 根据退出状态码判断日志级别为INFO或者ERROR
	# 判断退出状态码是否为0,
	#是的话日志级别为INFO,
	#不是的话为ERROR
	[[ ${exit_code} -eq 0 ]] && a=INFO || a=ERROR

	# 读取变量值, 逐行打印日志
	echo "${cmd_output}" | 
	while IFS= read -r line; do
		# 如果命令的格式是[[ ]]则不输出,这仅是测试命令的,返回信息无意义
		if [[ ! "${cmd}" == "[["*"]]" ]]
		then
			logger "$line" ${a}
		fi
	done
	return ${exit_code}
}

# 备份原文件
# 将原文件重命名为原文件名+当前日期
function bak_old(){
	old_path=$1
	# 当前备份文件是否存在
	if [[ -e ${old_path} ]]; then
		# 备份文件名
		bak_path=${old_path}.${cur_date}

		# 当前备份文件名是否存在
		# 如果存在的话删除
		if [[ -e ${bak_path} ]]; then
			sudo rm -rf ${bak_path}
		fi

		# 备份文件
		mv ${old_path} ${bak_path}
	fi
}

# 读取properties配置文件
# 将配置项读入到conf_map字典中
declare -A conf_map
function get_conf(){
	config="$1"
	if [[ -f "$config" ]]; then
		while IFS='=' read -r key value
		do
			key="${key#"${*%%[![:space:]]*}"}"
			key="${key%"${_##*[![:space:]]}"}"

			value="${value#"${*%%[![:space:]]*}"}"
			value="${value%"${_##*[![:space:]]}"}"
			#key="${key//[[:blank:]]/}"
			#value="${value//[[:blank:]]/}"
			## '.'替换为'-'
			#key=$(echo $key | tr '.' '_')
			## 不处理注释符＃起始的key
			if [[ -n "${key}" ]] && [[ -z $(echo "$key" | grep -P '^\s*#+.*' ) ]]; then
				conf_map["${key}"]="${value}"
				logger "$key = $value"
				#logger "key=$key value=$value"
			fi
		done < "$config"
		#for key in ${!conf_map[@]}; do
		#	logger "conf_map[${key}] = ${conf_map[${key}]}"
		#done
	fi
}

# ip地址转换
# 源格式:192.168.1.32
# 目标格式:192168001032
function convert_IP(){
	# IP地址
	ip="$1"
	
	# IP地址转数组
	OLD_IFS=${IFS}
	IFS=$'.'
	ip_fragments=(${ip})
	IFS=${OLD_IFS}

	echo "$(printf '%03d%03d%03d%03d' ${ip_fragments[@]})"
}

## 必须执行的命令
## option execuate command
## 第1个参数: 执行的命令
## 第2个参数: 执行成功的信息
## 第3个参数: 执行失败的信息
## 第4个参数: 是否必须执行成功
## 第1个参数必须, 2,3,4可选
## 如只一个参数的话,与myexec函数相同
## 多个参数,前一个参数必须不为空,可用引号占位
## 如: 一个必须执行成功的命令,执行成功返回"success", 执行不成功返回error
##     oexec "some command" "success" ERROR "need"
## 如: 一个必须执行成功的命令,执行成功不返回,执行不成功返回error
##     oexec "some command" "" ERROR "true"
## 如: 一个不必须执行成功的命令,执行成功不返回,执行失败返回error
##     oexec "some command" "" ERROR
function oexec(){
	# 要执行的命令
	cmd="${1:-}"
	# 执行成功的信息
	success_msg="${2:-}"
	# 错误信息
	error_msg="${3:-}"
	# 是否必须执行成功, 如果没有的话,默认为非必须
	need_success="${4:-false}"

	# 如果need_success的值是need的话,转为true
	[[ "${need_success}" == "need" ]] && need_success=true

	myexec "${cmd}"
	exit_code=$?

	# 判断待执行的命令是否为空
	if [[ -z "${cmd}" ]]; then
		# 为空警告,但是正常执行
		logger "您执行的是一个空字符串" WARN
	else
		# 执行成功的处理
		if [[ ${exit_code} -eq 0 ]]; then
			# 如果执行成功的消息不为空则打印
			[[ -n "${success_msg}" ]] && logger "${success_msg}" INFO
		else
			# 执行失败的处理
			# 执行失败有两种情况:
			#	1. 就是命令执行失败
			#	2. 命令是检测的,检测结果没有通过,这种情况下则不是失败
			if ( [[ ! "${error_msg}" == *\[FAIL\] ]] && [[ ! "${error_msg}" == *\[失败\] ]] ) \
				|| [[ "${error_msg}" == *检查* ]]  \
				|| [[ "${error_msg}" == *测试* ]]  \
				|| [[ "${cmd}" == "[[ "* ]]         \
				|| [[ "${cmd}" == "test "* ]]
			then

				# 如果执行失败的消息不为空则打印
				if [[ "${need_success}" == "true" ]]; then
					[[ -n "${error_msg}"   ]] && logger "${error_msg}" ERROR
				else
					[[ -n "${error_msg}"   ]] && logger "${error_msg}" WARN
				fi

			else
				# 如果执行失败的消息不为空则打印
				[[ -n "${error_msg}"   ]] && logger "${error_msg}" ERROR

				# 执行失败时同时打印命令
				logger "执行的命令:--> " ERROR
				logger "${cmd}" ERROR
			fi

			# 根据参数判断执行失败后是否退出整个程序
			if [[ "${need_success,,}" == "true" ]]; then
				logger "此为必须执行成功的命令, 退出..." ERROR
				exit ${exit_code}
			fi
		fi
	fi

	logger "exit_code=${exit_code}" DEBUG
	return ${exit_code}
}

# 执行命令并对执行结果进行处理
# 第1个参数: 需要执行的命令
# 第2个参数: 命令功能描述
# 第3个参数: 是否必须成功
# 第4个参数: 命令执行结果状态信息
# (执行正常是什么信息, 执行失败是什么信息)
# 默认成功的状态是SUCCESS
# 默认失败的状态是FAIL
# 格式为  PASS:FAIL
# super exec
function sexec(){
	# 要执行的命令
	cmd=${1:-""}

	# 命令功能描述
	# 对字符串进行首尾去除空白字符
	# 首部去除
	: "${2#"${2%%[![:space:]]*}"}"
	# 尾部去除
	: "${_%"${_##*[![:space:]]}"}"
	# 处理结果,默认为空
	info="${_:-""}"

	# 如果info为cmd则把命令功能描述指向命令本身
	[[ "${info}" == "cmd" ]] && info=${cmd}

	# 再去掉重复的空格 
	info="$(echo ${info} | tr -s ' ')"

	# 是否必须执行成功, 如果没有的话,默认为非必须
	need_success=${3:-false}

	# 命令执行结果状态,默认PASS:FAIL
	status_info=${4:-PASS:FAIL}

	# 对返回信息进行标准化处理
	# 最终返回的格式为:
	# 2022-06-15 20:15:19 [ INFO] 命令描述信息 ------------------------- [PASS]
	info_length=$(echo ${info} | wc -L)
	if [[ -n "${info}" ]]; then
		if [[ ${info_length} -lt 100 ]]; then
			# 拼接命令描述与 ------------------
			# 尽量让所有日志消息等长
			# ${#info}也能获取变量的长度,但是中英混的话会出现异常, 故用$(echo ${info} | wc -L)的方式
			info="${info} $(printf '%*.*s' 0 $(( 100 - ${info_length})) ${pad})"
		else
			info="${info} ---"
		fi

		# 执行成功返回的信息
		success_msg="${info} [${status_info%:*}]"

		# 执行失败返回的信息
		error_msg="${info} [${status_info#*:}]"
	else
		# 执行成功返回的信息
		success_msg=""

		# 执行失败返回的信息
		error_msg=""
	fi	

	oexec "${cmd}" "${success_msg}" "${error_msg}" "${need_success}"
	return  $?
}

