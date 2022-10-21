#!/usr/bin/zsh
############################# 打印变量值,调试时打开 ############################
# 需要安装except包
#set -e
#set -x

############################# 基础必须参数 #####################################
# parameters
cur_dir=$( cd $(dirname $0); pwd )
# 当前时间
cur_date=$(date "+%Y%m%d")
# 当前脚本名
file_name="${0##*/}"
# 配置文件名
conf_file=conf.properties


# 加载公共方法
################################# 加载公共方法 ##################################
# commons.sh脚本存放公共常用方法及变量
# commons.sh脚本通常存放在主程序的同级目录下
# commons.sh脚本如果不在同级目录下,则去上级目录下的commons目录下找
# 如果还是没有退出
[[ -f ${cur_dir}/commons.sh ]] && commons_file="${cur_dir}/commons.sh"
[[ -f ${cur_dir%/*}/commons/commons.sh ]] && commons_file="${cur_dir%/*}/commons/commons.sh"

if [[ -f ${commons_file} ]] ; then
    source ${commons_file}
    logger "commons.sh加载完成, 路径:--> ${commons_file}" INFO
	logger
else
    echo "commons.sh加载失败, 没有在当前目录及上级目录/commons下找到commons.sh  退出..."
    exit -1
fi

# 日志文件和目录
# 日志文件存放在主程序目录下的logs目录
# 日志文件与主程序文件同名,不同后缀
# 数据目录
log_level=INFO
#log_level=DEBUG
log_dir="${cur_dir}/logs"
log_file=${log_dir}/${file_name%.*}.log
[[ ! -d ${log_dir}          ]] && mkdir -p ${log_dir}
################################# 加载配置文件 ##################################
# get_conf 方法会将配置文件读取到conf_map字典里
# 除了配置文件,再给一个默认参数
get_conf ${cur_dir}/${conf_file}
container_home="${conf_map['container.home']:=/opt/huan-ling}"
module_version="${conf_map['release.version']:=dev}"
ch_host="${conf_map['db.ch.host']:=127.0.0.1}"
ch_port="${conf_map['db.ch.port']:=9000}"
ch_user="${conf_map['db.ch.user']:=wedo}"
ch_password="${conf_map['db.ch.password']:=123123}"
module_list="${conf_map['module.list']:=[dns-base, dns-business, dns-resources, dns-worksheet, dns-security-analysis, dns-dimension]}"
module_list=${module_list//\[/}
module_list=${module_list//]/}
module_list=${module_list//,/ }
module_list=(${module_list})
deploy_type=${deploy_type:=install}

############################### 当前程序需要的参数 ############################## 
work_dir=${cur_dir}

############################## 解析命令行传的参数 ###############################
# getopt指定命令行可以给脚本传哪些参数
# -a 为短选项(不需要值) ,这里没有定义
# -o 为短选项(需要值), 这里定义了-h, -p, -u, -P等等
# --long 为长选项需要值, 这里定义了--host, --port, --username, --password等等,
ARGS=$(getopt -a -o v:d:h:p:u:P:t:c  --long release_version:,ch_host:,ch_port:,ch_user:,ch_password:,type:,help -- "$@")

# 重排选项
if [ $? != 0 ];then
    echo "Terminating..."
    exit 1
fi


eval set -- "${ARGS}"


# 解析命令行参数
while :
do
    case "$1" in
        -v|--release_version)
            module_version=${2##*/}
            shift
            ;;
        -h|--ch_host)
            ch_host=${2}
            shift
            ;;
        -p|--ch_port)
            ch_port=${2}
            shift
            ;;
        -u|--ch_user)
            ch_user=${2}
            shift
            ;;
        -t|--type)
            deploy_type=${2}
            shift
            ;;
        -P|--ch_password)
            ch_host=${2}
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
            logger "$1" INFO
            logger "Internal error!" INFO
            exit 1
            ;;
    esac
        shift
done

#######################################  环境检查 ######################################
docker_compose_file=${container_home}/docker-compose.yml
type docker            1>/dev/null 2>&1 && logger "检查通过: docker"              INFO|| { logger "请看README文档, 服务没有安装: docker"            "ERROR" ; exit -1; }
type docker-compose    1>/dev/null 2>&1 && logger "检查通过: docker-compose"      INFO|| { logger "请看README文档, 服务没有安装: docker-compose"    "ERROR" ; exit -1; }
type unbuffer          1>/dev/null 2>&1 && logger "检查通过: expect-devel"        INFO|| { logger "请看README文档, 服务没有安装: expect-devel"      "ERROR" ; exit -1; }
type clickhouse-client 1>/dev/null 2>&1 && logger "检查通过: clickhouse-client"   INFO|| { logger "请看README文档, 服务没有安装: clickhouse-client" "ERROR" ; exit -1; }
[[ -f ${docker_compose_file} ]]         && logger "检查通过: docker-compose.yml"  INFO|| { logger "请看README文档, 必须在业务分析服务器执行"        "ERROR" ; exit -1; }

logger "环境检查结束..." INFO
logger 

#######################################  参数检查 ######################################
logger "参数配置说明:" INFO

logger " huan-ling项目目录: ${container_home}" INFO

logger "当前部署的模块版本: ${module_version}" WARN

for ele in ${module_list[@]}; do logger "支持一键部署的模块: ${ele}" WARN; done
logger "如果模块不支持一键部署请在配置文件(${conf_file})中添加,配置项: module.list " WARN
logger ""

logger "ClickHouse节点地址: ${ch_host}" WARN
logger "ClickHouse节点端口: ${ch_port}" WARN
logger "ClickHouse节点用户: ${ch_user}" WARN

[[ ${conf_map['deploy.clickhouse.create.dim']}       == "true" ]] && logger "部署时将 重新创建 ClickHouse的   dim   数据库(原有数据将全部删除!!!)" WARN|| logger "部署时将 忽忽略略 ClickHouse的   dim   数据库"
[[ ${conf_map['deploy.clickhouse.create.src']}       == "true" ]] && logger "部署时将 重新创建 ClickHouse的   src   数据库(原有数据将全部删除!!!)" WARN|| logger "部署时将 忽忽略略 ClickHouse的   src   数据库"
[[ ${conf_map['deploy.clickhouse.create.dws']}       == "true" ]] && logger "部署时将 重新创建 ClickHouse的   dws   数据库(原有数据将全部删除!!!)" WARN|| logger "部署时将 忽忽略略 ClickHouse的   dws   数据库"
[[ ${conf_map['deploy.clickhouse.create.rpt']}       == "true" ]] && logger "部署时将 重新创建 ClickHouse的   rpt   数据库(原有数据将全部删除!!!)" WARN|| logger "部署时将 忽忽略略 ClickHouse的   rpt   数据库"
[[ ${conf_map['deploy.clickhouse.create.dim_dict']}  == "true" ]] && logger "部署时将 重新创建 ClickHouse的dim_dict 数据库(原有数据将全部删除!!!)" WARN|| logger "部署时将 忽忽略略 ClickHouse的 dim_dict 数据库"
[[ ${conf_map['deploy.clickhouse.import.dim']}       == "true" ]] && logger "部署时将 重新导入 ClickHouse的   dim   数据库(原有数据将全部删除!!!)" WARN|| logger "部署时将 不重导入 ClickHouse的   dim   数据库"
[[ ${conf_map['deploy.postgresql.create.huan-ling']} == "true" ]] && logger "部署时将 重新创建 PostgreSQL的  huan   数据库(原有数据将全部删除!!!)" WARN|| logger "部署时将 忽忽略略 PostgreSQL的   huan  数据库"


read -p "请确认以上参数及配置,一旦开始部署,不可自动回退; 如部署失败,请手动解决,输入Yes继续:" confirm_install
if [[ "${confirm_install}" == "Yes" ]] ; then
	logger "确认以上参数及配置" INFO 
	logger "开始部署..." INFO 
else
	logger "您没有输入Yes, 即将退出..." WARN
	exit -1
fi

####################################### 开始部署  ######################################
# 判断是否部署成功
deploy_success=none
for module_name in ${module_list[@]};do
	# 重置初始路径
	cd ${cur_dir}

	# 拼装模块名及版本号
	module_info=${module_name}_${module_version}
	module_dir=${cur_dir}/${module_info}
	module_file=${cur_dir}/${module_info}.tar.gz

	# 判断模块部署包是否存在
	sexec "[[ -f ${module_file} ]] " "检测部署包${module_file##*/}" optional "PASS:不存在"|| continue

	# 解压后各部分的目录
	# 数据引擎路径
	de_dir=${module_dir}/${module_info}_de/${module_name}
	# 后端路径
	be_dir=${module_dir}/${module_info}_be/${module_name}
	# 前端路径
	wb_dir=${module_dir}/${module_info}_wb/${module_name}
	# 配置文件路径
	conf_dir=${module_dir}/${module_info}_configs
	# 维表数据路径
	data_dir=${module_dir}/${module_info}_data
	# SQL文件路径
	sqls_dir=${module_dir}/${module_info}_sqls/install
	# GateWay路径
	gateway_dir=${module_dir}/gateway_routes
	# pg建表路径
	put_container_dir=/root/${module_name}

	logger "开始部署模块: ${module_name}, 版本: ${module_version}" INFO 

	# 判断模块解压目录是否存在
	sexec "sudo rm -rf ${module_dir}" "解压路径($module_info)已存在, 删除" need

	# 部署包文件完整性检查
	#oexec "gzip -t ${module_file}"   "文件完整性检查(${module_file##*/}):--> 通过"  "部署包已经损坏 :--> ${module_file}" need
	sexec "gzip -t ${module_file}"   "文件完整性检查:${module_file##*/}"  need

	# 解压部署包
	sexec "tar -zxvf ${module_file}" "解压部署包${module_file##*/}" need
	logger 
	
	# 开始PostgreSQL建表
	pg_create_table="deploy.postgresql.create.huan-ling"
	if [[ "${conf_map[${pg_create_table}]}" == "true" ]]; then
		logger "开始为PostgreSQL的huan-ling数据库创建表,索引,视图等..." INFO

		# 删除PostgreSQL容器已经存在的SQL文件目录
		sexec "docker exec -it postgresql01 rm -rf ${put_container_dir}" "删除PostgreSQL容器已存在的SQL文件目录(${put_container_dir})" optional "SUCCESS:目录不存在"

		# PostgreSQL容器创建文件目录
		sexec "docker exec -it postgresql01 mkdir -p ${put_container_dir}" "PostgreSQL容器创建文件目录(${put_container_dir})" need

		# 复制SQL文件到PostgreSQL容器(不包括需要导入的数据)
		sexec "docker cp ${sqls_dir}/pg postgresql01:${put_container_dir}" "复制待执行的SQL文件到PostgreSQL容器(${sqls_dir##*/}/pg)" need
		logger 

		file_list=($(ls ${sqls_dir}/pg))
		for ele in ${file_list[@]}; do
			logger "PostgreSQL待执行的SQL文件:--> (${ele})" INFO
		done

		# PostgreSQL警告说明
		logger "提醒:PostgreSQL执行日志中类似于这样: " WARN
		logger "psql xxx.sql xxx NOTICE: Table xxx does not exist, skipping可忽略," WARN
		logger "它是PostgreSQL执行drop  table table_name if exists产生的" WARN
		logger 

		for f in ${file_list[@]}; do
			sexec "docker exec -it --user root postgresql01 psql --host=localhost --port=5432 --user=data_engine --dbname=huan-ling -P pager=off -v ON_ERROR_STOP=true -f ${put_container_dir}/pg/${f}" "在PostgreSQL的huan数据库执行SQL文件: ${f}" need
		done
		logger "PostgreSQL的huan-ling数据库部署完毕" INFO
		logger
	else
		logger "根据配置参数设置, 跳过PostgreSQL建表" WARN
		logger "如需要设置PostgreSQL重新建表" WARN
		logger "请在配置文件${conf_file}中配置:--> ${pg_create_table}=true" WARN
	fi

	# 开始向PostgreSQL导入数据
	pg_import_data=deploy.postgresql.import.huan-ling
	if [[ "${conf_map[${pg_import_data}]}" == "true" ]]; then

		logger "开始为PostgreSQL的huan-ling数据库导入数据..." INFO
		# PostgreSQL容器清除旧数据: 如果目录存在则删除重建
		sexec "docker exec -it --user root postgresql01 bash -c \"rm -rf ${put_container_dir}/data && mkdir -p ${put_container_dir}/data \";" "PostgreSQL容器数据目录重建" need
		

		file_list=($(find ${data_dir} -name "*.csv.tar.gz" -type f))
		for ele in ${file_list[@]}; do
			logger "PostgreSQL待导入的csv文件:--> ${ele//${data_dir}\//}" INFO
		done
		logger

		logger "上传到PostgreSQL容器的目录:${put_container_dir}/data"
		# 遍历data目录下所有的.tar.gz文件,将数据导入到PostgreSQL
		for file_path in ${file_list[@]};do
			# 文件检查 规则1: tar.gz不能不完整
			sexec "gzip -t ${file_path}"       "文件完整性检查(${file_path##*/}" need

			# 解压.tar.gz数据文件,如果解压失败,立即退出
			tmp_dir=/tmp/huan-ling
			sexec "rm -rf ${tmp_dir} && mkdir -p ${tmp_dir}" "为PostgreSQL数据文件创建临时目录${tmp_dir}" "need"

			set -e
			decompressed_file_list=($(tar -zxvf ${file_path} -C ${tmp_dir}))
			if [[ $? -ne 0 ]]; then
				logger "解压文件失败,请检查检查该文件:--> ${file_path}"
			fi
			set +e
			logger "解压后的数据文件: ${decompressed_file_list[*]}" DEBUG

			for dfile in ${decompressed_file_list[@]}; do
				dfile=${tmp_dir}/${dfile}
				#if [[ -f ${dfile} ]] && [[ ! ${dfile} =~ ^\..* ]]; then
				if [[ -f ${dfile} ]]; then
					# 文件检查 规则2: 不能是隐藏文件
					sexec "[[ ! "${dfile##*/}" =~ ^\..* ]]" "文件命名检查(${dfile##*/})"  need

					table_name=${dfile##*/}
					table_name=${table_name%%-*}
					sexec "docker exec -it --user root postgresql01 psql --host=localhost --port=5432 --user=data_engine --dbname=huan-ling -P pager=off -v ON_ERROR_STOP=true -c \"truncate table public.${table_name}\"" "清空表(${table_name})" need
					sexec "docker cp ${dfile} postgresql01:${put_container_dir}/data" "上传数据到PostgreSQL容器: ${dfile}" need
					#logger "docker exec -it --user root postgresql01 psql --host=localhost --port=5432 --user=data_engine --dbname=huan-ling -P pager=off -v ON_ERROR_STOP=true -c \"\\copy public.${table_name} from '${put_container_dir}/data/${dfile##*/}'  with csv header ENCODING 'UTF8'  NULL AS 'null'\"" DEBUG
					sexec "docker exec -it --user root postgresql01 psql --host=localhost --port=5432 --user=data_engine --dbname=huan-ling -P pager=off -v ON_ERROR_STOP=true -c \"\\copy public.${table_name} from '${put_container_dir}/data/${dfile##*/}'  with csv header ENCODING 'UTF8'  NULL AS 'null'\"" "${dfile##*/} 导入数据到表 ${table_name}" need
				fi
				logger
				#rm -f ${dfile}
			done
		done
		logger
	else
		logger "根据配置参数设置, 跳过PostgreSQL数据导入, " WARN
		logger "如需要设置PostgreSQL导入数据" WARN
		logger "请在配置文件${conf_file##*/}中配置:--> ${pg_import_data}=true" WARN
	fi
	logger


	# 开始建ClickHouse表
	# clickhouse数据库目前有:dim, src, dws, rpt,必须保证dim库先建
	# 因为其他数据库有可能依赖于dim库

	# 对数据库进行排序,保证dim数据库最先建,src, dws, rpt随后,其他的再后
	# 先保证dim, src, dws, rpt在前,其他数据库追加到列表
	db_list=(dim src dim_dict dws rpt)
	for k in ${!conf_map[@]}; do

		# 判断配置文件中配置项以deploy.clickhouse.create.开头
		if [[ "${k}" =~ ^deploy.clickhouse.create.* ]]; then
			# 获取数据库名称
			db_name=${k//deploy.clickhouse.create./}

			# 判断该数据库是否在数据库列表
			# 不在的话则追加到数据库数组末尾,以保证顺序
			if [[ ! "${db_list[*]}" =~ "${db_name}" ]]; then
				db_list[${#db_list[@]}]=${db_name}
				logger "在配置项${k}中发现新的数据库${db_name}, 已添加到数据库列表" INFO
			fi
		fi
	done
	logger "加载配置完毕, 待部署的数据库: (${db_list[*]})"
	
	# 待执行的SQL文件目录
	ch_dir=${sqls_dir}/ch
	# 先查询集群都有哪些节点:
	ch_list=($(clickhouse-client --host=${ch_host} --port=${ch_port} --user=${ch_user} --password=${ch_password} --query="select host_name from system.clusters where cluster='clickhouse_cluster'"))
	logger "clickhouse-client --host=${ch_host} --port=${ch_port} --user=${ch_user} --password=${ch_password} " DEBUG
	logger "ClickHouse_cluster 集群节点:  (${ch_list[*]})" INFO
	logger

	# 判断是否配置主机名到IP地址的映射,该项很关键,很多地方都会用到
	sexec "[[ '${ch_list[*]}' =~ 'clickhouse0' ]]" "检测ClickHouse服务器配置IP地址映射" need

	# 根据排序后的数据库列表,依次遍历部署
	for db_name in ${db_list[@]}; do
		# 根据以往的情况,dim, src数据库仅在第一次的时候需要部署
		# 故最好根据情况配置哪些数据库需要重建
		if [[ "${conf_map[deploy.clickhouse.create.${db_name}]}" == "true" ]]; then
			
			# 获取待执行的SQL文件
			ch_sql_list=($(find ${ch_dir} -name "*.sql" -type f | sort))
			#ch_sql_list=($(find ${ch_dir} -name "*${db_name}.sql" -type f))
			#ch_sql_list=($(find ${ch_dir} -name "${db_name}.${db_name}_*.sql" -type f))

			
			# 判断是否有SQL文件存在
			if [[ ${#ch_sql_list[@]} -eq 0 ]]; then
				logger "ClickHouse ${db_name}数据库: ${ch_dir//${cur_dir}\//} 目录下没有SQL文件需要部署" INFO
			fi

			# 在ClickHouse集群中执行所有SQL文件
			# 遍历每一个SQL文件
			for sf  in ${ch_sql_list[@]}; do
				if [[ "${sf##*/}" =~ ^[0-9]{2}_dns_${db_name}.sql ]] || [[ "${sf##*/}" =~ ^${db_name}.${db_name}_.*\.sql ]]; then
					# dim, src, dim_dict的SQL文件格式为:01_dns_dim.sql
					# 之所以以数字开头, 是因为dim, src数据库特别重要,且基础,需要保证SQL文件的执行顺序
					if [[ "${db_name}" == "src" ]] || [[ "${db_name}" == "dim" ]] || [[ "${db_name}" == "dim_dict" ]];then
						if [[ ! "${sf##*/}" =~ ^[0-9]{2}_.*_${db_name}\.sql ]] && [[ "${tmp}" == "${db_name}"  ]]; then
							logger "sql文件(${sf##*/})命名不规范, 跳过. dim, src, dim_dict的SQL文件格式为: xx_dns_${db_name}.sql" WARN
							continue
						fi
					elif [[ "${db_name}" == "dws" ]] || [[ "${db_name}" == "rpt" ]]; then
						# dws, rpt的SQL文件格式为rpt.rpt_xxxxxxx.sql
						# dws, rpt表属于下游, 不关注执行顺序
						if [[ ! "${sf##*/}" =~ ^${db_name}\.${db_name}_.*\.sql ]]; then
							logger "sql文件(${sf##*/})命名不规范, 跳过. dws, rpt的SQL文件格式为${db_name}.${db_name}_xxxxxxx.sql" WARN
							if [[ ! "${sf##*/}" =~ ^[0-9]{2}_.*_${db_name}\.sql ]] && [[ "${tmp}" == "${db_name}"  ]]; then
								continue
							fi
						fi
					fi
					# 遍历每一个ClickHouse集群节点
					for chh in ${ch_list[@]};do
						sexec "clickhouse-client --host=${chh} --port=${ch_port} --user=${ch_user} --password=${ch_password} --multiquery < ${sf}" "${chh}执行SQL文件: ${sf##*/}" need
					done
				fi
			done
		else
			logger "ClickHouse: 根据配置文件, 忽略 ${db_name} 数据库" INFO
		fi
	done

	logger "ClickHouse数据库: 部署完成" INFO
	logger
	# 开始部署数据引擎容器
	logger "开始部署数据引擎容器(engine01...)" INFO

	# 数据引擎容器挂载目录根
	de_module_root_dir=${container_home}/engine/.modules

	# 当前模块的挂载目录
	de_module_dir=${de_module_root_dir}/${module_name}

	# 待部署的文件
	file_list=($(ls ${de_dir} 2>/dev/null))
	logger "待部署的文件:--> ${file_list[*]//${de_dir}\//}" INFO
	logger "数据引擎容器部署目录:--> ${de_module_dir}" INFO

	# 判断数据引擎的部署文件存在
	if [[ ${#file_list[@]} -ne 0 ]]; then
		sexec "bak_old ${de_module_dir}"         "备份数据引擎容器旧代码"  need
		sexec "cp -r ${de_dir} ${de_module_dir}" "部署数据引擎容器"        need
	else
		logger "${module_name} 模块没有数据引擎服务, 跳过..." WARN
	fi
	logger

	logger "开始部署airflow scheduler容器(dag调度文件)..." INFO

	# 部署包文件路径
	de_schedule_dir=${de_dir}/schedule

	# 部署根路径
	dag_root_dir=${container_home}/airflow/dags

	# 模块部署路径
	dag_module_dir=${dag_root_dir}/${module_name}

	# 待部署的文件
	file_list=($(ls ${de_schedule_dir} 2>/dev/null))

	# 判断任务调度的部署文件是否存在
	if [[ ${#file_list[@]} -ne 0 ]]; then

		# 删除旧dag调度文件
		sexec "sudo rm -rf ${dag_module_dir}" "删除旧的dag调度文件" need

		# 创建调度目录
		mkdir -p ${dag_module_dir}

		# 部署dag调度文件
		sexec "cp -r ${de_schedule_dir}/* ${dag_module_dir}" "部署airflow Scheduler容器完成(dag调度)" need
	else
		logger "${module_name} 模块没有dag调度" WARN
	fi
	logger
#fi


	# 开始部署业务后端容器(backend01容器)
	logger "开始部署后端容器(backend01)..." INFO

	# 后端容器挂载根目录
	dk_be_dir=${container_home}/backend

	# 后端服务根挂载目录
	dk_be_modules_root=${dk_be_dir}/.modules

	# 后端服务挂载目录
	dk_be_module_dir=${dk_be_modules_root}/${module_name}

	# 部署文件列表
	file_list=($(ls ${be_dir} 2>/dev/null))

	# 判断该模块是否有后端服务
	if [[ ${#file_list[@]} -ne 0 ]]; then
		# 判断后端服务根挂载目录是否存在
		if [[ ! -d ${dk_be_modules_root} ]]; then
			logger "后端模块挂载目录(${dk_be_modules_root})不存在 ,创建..." INFO
			mkdir -p ${dk_be_dir}/.modules

			# 赋予权限
			chmod -R 777 ${dk_be_dir}/.modules
		fi

		# 判断后端服务是否存在
		# 存在即备份
		if [[ -d ${dk_be_module_dir} ]]; then
			sexec "bak_old \"${dk_be_module_dir}\"" "备份后端服务"  
		fi

		# 部署后端服务
		sexec "cp -r ${be_dir} ${dk_be_modules_root}" "部署后端服务" need

		# supervisorctl配置文件
		module_supervisor_conf=${be_dir}/${module_name}.ini

		if [[ -f ${module_supervisor_conf} ]]; then
			sexec "docker cp ${module_supervisor_conf} backend01:/etc/supervisor.d/" "部署supervisord配置文件(${module_supervisor_conf##*/})"
		fi
	else
		logger "${module_name} 模块没有后端服务, 跳过..." WARN
	fi
	logger

	logger "开始部署gateway..." INFO
	# 部署的文件列表
	file_list=($(ls ${gateway_dir} 2>/dev/null))

	logger "gateway 需要部署的文件:--> ${file_list[*]}" DEBUG

	# 判断是否有gateway需要部署
	if [[ ${#file_list[@]} -ne 0 ]]; then
		dk_gateway_dir=${container_home}/gateway
		sexec "cp -r ${gateway_dir}/* ${dk_gateway_dir}/conf/route" "部署gateway容器" need
	else
		logger "${module_name} 模块没有gateway配置需要部署,跳过..." WARN
	fi
	logger
	# 安装前端模块
	logger "开始部署前端模块(emsui01)..." INFO
	file_list=($(ls ${wb_dir} 2>/dev/null))
	logger "前端模块需要部署的文件:--> ${file_list[*]}" DEBUG

	# 判断前端是否需要部署
	if [[ ${#file_list[@]} -ne 0 ]]; then
		dk_wb_dir=${container_home}/emsui
		sexec "cp -r ${wb_dir} ${dk_wb_dir}/plugins/" "部署前端模块" need

		# 添加页面菜单
		t_role_path=${wb_dir}/t_role
		if [[ -f ${t_role_path} ]]; then

			logger "开始配置前端页面菜单..." INFO
			append_menus="$(cat ${t_role_path})"

			# 去掉换行
			append_menus="${append_menus//$'\r\n'/}"
			append_menus="${append_menus//$'\n'/}"

			# 去掉空格
			append_menus="${append_menus// /}"

			# 如果结果有逗号的话去掉逗号
			if [[ "${append_menus}" =~ .,$ ]]; then
				append_menus="${append_menus%,}"
			fi
			logger "待添加的页面菜单:--> ${append_menus}" INFO
			logger 

			# 从PostgreSQL数据库是获取原来的菜单
			old_menus="$(unbuffer docker exec -it --user root postgresql01 psql --host=localhost --port=5432 --user=backend_auth --dbname=ems_auth -A -t -c 'select menus from public.t_role where id=1;')"

			# 遍历需要添加的菜单,看哪些原来菜单没有的添加进去
			# 先去掉不必要的字符--> [ ] \r\n \n 空格
			old_menus=${old_menus//\[/}
			old_menus=${old_menus//]/}
			old_menus=${old_menus// /}
			old_menus="${old_menus//$'\r\n'/}"
			old_menus="${old_menus//$'\n'/}"
			old_menus="${old_menus//$'\r'/}"

			logger "旧页面菜单:--> ${old_menus}" INFO
			# 将需要添加的菜单转为列表
			OLD_IFS=$IFS
			IFS=','
			append_list=(${append_menus})
			menu_list=(${old_menus})
			IFS=$OLD_IFS

			logger
			logger "由于旧菜单集与待添加的菜单有重叠，开始对待添加的菜单和旧菜单取并集..." INFO
			# 遍历需要添加的菜单,看哪些原来菜单没有的添加进去
			for menu in ${append_list[@]};do
				if [[ "${old_menus[*]/${menu}/}" == "${old_menus}" ]]; then
					logger "需要新增的菜单---------------> ${menu}" INFO
					menu_list[${#menu_list[@]}]=${menu}
				fi
			done
			logger

			OLD_IFS=$IFS
			IFS=','
			new_menus="[${menu_list[*]}]"
			IFS=$OLD_IFS
			logger "取并集后， 新的页面菜单:--> ${new_menus}" INFO

			# 更新菜单
			new_menus="${new_menus//\"/\\\"}"
			logger "update t_role sql:--> " DEBUG
			logger "update public.t_role set menus='${new_menus}' where id=1;" DEBUG

			sexec "docker exec -it --user root postgresql01 psql --host=localhost --port=5432 --user=backend_auth --dbname=ems_auth -c \"update public.t_role set menus='${new_menus}' where id=1;\"" "PostgreSQL更新前端t_role" need
			#sexec "docker exec -it --user root postgresql01 psql --host=localhost --port=5432 --user=backend_auth --dbname=ems_auth -c \"update public.t_role set menus='${new_menus}' where id=1;\"" cmd need
		else
			logger "t_role file does not exists in ${wb_dir//${module_dir}\//}, skip..." WARN
		fi
	else
		logger "${module_name} 模块没有前端服务,跳过..." WARN
	fi

	logger "${module_name} 模块部署完成" INFO
	logger

	sexec "mv ${module_dir}.tar.gz ${module_dir}.tar.gz.bak" "重命名部署包 ${module_dir##*/}.tar.gz :--> ${module_dir##*/}.tar.gz.bak" 
	deploy_success=true
	logger
done


if [[ "${deploy_success}" == "true" ]]; then
	logger 
	logger "部署完成,开始重启相关容器" INFO
	sexec "docker restart airflow-scheduler01 &>/dev/null" "重启airflow任务调度容器(airflow-scheduler01)" optional "SUCCESS:失败,请手动重启"
	sexec "docker restart backend01 &>/dev/null"           "重启后端容器(backend01)"                      optional "SUCCESS:失败,请手动重启"
	sexec "docker restart gateway01 &>/dev/null"           "重启gateway容器(gateway01)"                   optional "SUCCESS:失败,请手动重启"
	sexec "docker restart emsui01 &>/dev/null"             "重启前端容器(emsui01)"                        optional "SUCCESS:失败,请手动重启"
	logger "相关容器重启完成, 请浏览器退出重新登陆,以加载更新"  WARN
	logger "重新登陆时,如果页面报\"page not found\",说明前端页面还没有重启完,等1分钟"  WARN
fi
