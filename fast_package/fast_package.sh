#!/bin/bash
############################################
## auth: wedo
## date: 2021-10-27 12:03:26
## commands: sh release_module.sh dns-resources v1.0.0_1.0.4
############################################
# must install maven

###################基础必须函数#######################
# parameters
cur_dir=$( cd $(dirname $0); pwd )
# 当前时间
cur_date=$(date "+%Y%m%d")
# 当前脚本名
file_name="${0##*/}"
# 配置文件名
conf_file=conf.properties
# 脚本主线程PID作为数据生成目录
main_pid="$$"

function myexec(){
	cmd=$*
	logger "execute command --> ${cmd}"
	${cmd} 2>&1 | 
	while IFS= read -r line; do
		logger "$line"
	done
}

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
type git          1>/dev/null 2>&1 && logger "检查通过: git"   INFO|| { logger "请看README文档, 服务没有安装: git"   "ERROR" ; exit -1; }
type wget         1>/dev/null 2>&1 && logger "检查通过: wget"  INFO|| { logger "请看README文档, 服务没有安装: wget"  "ERROR" ; exit -1; }
type mvn          1>/dev/null 2>&1 && logger "检查通过: maven" INFO|| { logger "请看README文档, 服务没有安装: maven" "ERROR" ; exit -1; }
type ssh          1>/dev/null 2>&1 && logger "检查通过: ssh"   INFO|| { logger "请看README文档, 服务没有安装: ssh"   "ERROR" ; exit -1; }
[[ $(ssh -T git@gitlab.com 1>/dev/null 2>&1) -eq 0 ]] && logger "检查通过: ssh"  INFO|| { logger "gitlab没有配置ssh无密钥登陆" "ERROR" ; exit -1; }

# 日志文件和目录
# 日志文件存放在主程序目录下的logs目录
# 日志文件与主程序文件同名,不同后缀
# 数据目录
log_level=INFO
#log_level=DEBUG
log_dir="${cur_dir}/logs"
log_file=${log_dir}/${file_name%.*}.log
[[ ! -d ${log_dir}          ]] && mkdir -p ${log_dir}

###############下面开始写自己的脚本###################
# -----------------本脚本参数-------------------------
# arguments
# 模块名
module_name=$1
# 需要打包的分支
branch_name=${2}
module_version=${branch_name##*/}
# 是否强制删除git clone源码(true/false)
force_delete_git=$3
ftp_server="ftp://192.168.8.100"

# -----------------必须的目录-------------------------
git_dir=${cur_dir}/GitLib
tmp_dir=${cur_dir}/tmp
module_dir=${git_dir}/${module_name}
release_dir=${cur_dir}/release/${module_name}_${module_version}

# 源代码中数据模块的路径
de_dir=${module_dir}/codes/engine/${module_name}
# 源代码中后端模块的路径
be_dir=${module_dir}/codes/services/${module_name}
# 源代码中前端模块的路径
wb_dir=${module_dir}/codes/web/${module_name}


# 部署包中数据模块的路径
de_release_dir=${release_dir}/${module_name}_${module_version}_de
# 部署包中后端模块的路径
be_release_dir=${release_dir}/${module_name}_${module_version}_be
# 部署包中前端模块的路径
wb_release_dir=${release_dir}/${module_name}_${module_version}_wb
sql_release_dir=${release_dir}/${module_name}_${module_version}_sqls
data_release_dir=${release_dir}/${module_name}_${module_version}_data
conf_release_dir=${release_dir}/${module_name}_${module_version}_configs


[[   -d ${release_dir}      ]] && rm    -rf ${release_dir}
# 创建相应的目录
[[ ! -d ${tmp_dir}          ]] && mkdir -p  ${tmp_dir}
[[ ! -d ${git_dir}          ]] && mkdir -p  ${git_dir}
[[ ! -d ${release_dir}      ]] && mkdir -p  ${release_dir}
[[ ! -d ${de_release_dir}   ]] && mkdir -p  ${de_release_dir}
[[ ! -d ${be_release_dir}   ]] && mkdir -p  ${be_release_dir}
[[ ! -d ${wb_release_dir}   ]] && mkdir -p  ${wb_release_dir}
[[ ! -d ${sql_release_dir}  ]] && mkdir -p  ${sql_release_dir}
#[[ ! -d ${data_release_dir} ]] && mkdir -p  ${data_release_dir}
[[ ! -d ${conf_release_dir} ]] && mkdir -p  ${conf_release_dir}

git_remote_url=${git_remote_url:=git@gitlab.com:}
git_project_url=${git_remote_url}/business-modules/${module_name}.git

# 打印基础信息
logger "begin to package deply compression file..."
logger "module_name=${module_name}"
logger "branch_name=${branch_name}"

logger "git clone path = ${git_dir/${cur_dir}\/}"
logger "git clone url = ${git_project_url}"
logger "current directory = ${cur_dir##*/}"

logger "necessary directory create finish"

logger "start to package deply compression file, module_name=${module_name}, branch=${branch_name}"

############################################ 下载更新源码 ##############################################
# 克隆GitLib源码,
# 源码不存在则克隆并切换到打包分支/标签
# 如果源码已克隆则切换到打包分支并拉取最新代码
# 如果用户指定强制重新克隆则先删除原有代码
if [[ "${force_delete_git}" != "true" ]];then
	if [[ -d ${module_dir} ]]; then
		logger "${module_name} project already clone from GitLib to local --> ${module_dir/${cur_dir}\/}"
		cd ${module_dir}
		sexec "git checkout ${branch_name}" cmd need
		logger "${module_name} switch to branch(tag) ${branch_name}"
		sexec "git pull" cmd need
		logger "${module_name} git pull finish"
	else
		logger "${module_name} project does not exists, I will clone it"
		git clone ${git_project_url} ${module_dir} --branch ${branch_name}
		logger "${module_name} clone finish"
	fi
else
	logger "user specify force delete ${module_dir} git source code"
	if [[ -d ${module_dir} ]]; then
		rm -rf ${module_dir}
	fi
	git clone ${git_project_url} ${module_dir} --branch ${branch_name}
	logger "${module_name} clone finish"
fi

cd ${module_dir}

if [[ ! -d ${release_dir} ]]; then
	logger "release dir does not exist, I will create it --> ${release_dir}"
	mkdir -p ${release_dir}
fi

logger  "${module_name} clone/update successfull!"

############################################ 添加t_role ##############################################
# module mate files
# t_role
t_role_path=${wb_dir}/t_role
if [[ -f ${t_role_path} ]];then
	cp ${t_role_path} ${release_dir}
	#cp ${TEMP_REPO_PATH}/codes/web/${module_name}/t_role ${TEMP_RELEASE_DIR_PATH} )
	logger "${t_role_path} get ready..."
else
	logger "${release_dir/${cur_dir}\//}/t_role does not exists, skip..."
fi

############################################ 添加gateway ##############################################
# gateway
gateway_dir=${release_dir}/gateway_routes
mkdir -p ${gateway_dir}
routes_files=($(find ${module_dir}/configs -name "*route*" -type f))
if [[ ${#routes_files[@]} -gt 0 ]]; then
	cp -r ${module_dir}/configs/*route* ${gateway_dir}
	logger "gateway config files get ready..."
else
	logger "there is no routes config files in gateway, skip..."
fi

# package json
package_path=${module_dir}/package.json
if [[ -f ${package_path} ]]; then
	cp -r ${package_path}  ${release_dir}
fi
logger "${release_dir/${cur_dir}\/}/package.json get ready..."

# module mate
version_path=${module_dir}/.version
touch ${version_path}
echo "module_name=${module_name}" > ${version_path}
echo "branch_name=${branch_name}" >> ${version_path}
logger "${version_path/${cur_dir}\/} get ready..."


############################################ 打包前端模块 ##############################################
# package web
if [[ -d ${wb_dir} ]];then
	logger  "copy web module files to deply directory"
	cp -r ${wb_dir} ${wb_release_dir}
	logger "web service module get ready..."
else
	logger "there are no web module service in ${module_name}, skip..."
fi
logger ""

############################################ 打包后端模块 ##############################################
# package backend service
logger "start compile backend service module "
if [[ -d ${be_dir} ]]; then
	cd ${be_dir}
	sexec "mvn clean" need
	sexec "mvn package" need
	cd ${be_dir}/target
	mkdir -p ${module_name}_${module_version}_be/${module_name}
	[[ ! -d ${be_release_dir}/${module_name} ]] && mkdir -p ${be_release_dir}/${module_name}
	cp -r config/ ${be_release_dir}/${module_name}
	cp -r lib/    ${be_release_dir}/${module_name}
	cp -r *.jar   ${be_release_dir}/${module_name}
	cp -r ${module_dir}/scripts/start_script.sh    ${be_release_dir}/${module_name}
	cp -r ${module_dir}/scripts/${module_name}.ini ${be_release_dir}/${module_name}
	cd ${module_dir}
else
	logger "${module_name} does not have backend service, skip..."
fi
logger "backend service module get ready..."
logger ""


############################################ 打包数据引擎模块 ##############################################
# 打包数据引擎模块
logger "de_dir=${de_dir/${cur_dir}\/}"
if [[ -d ${de_dir} ]]; then
	logger  "copy data engine module to package"
	cp -r ${de_dir} ${de_release_dir} 
else
	logger "there is no data engine module service in ${module_name}"
fi
logger "data engine service module data get ready..."
logger ""

############################################ 打包配置模块 ##############################################
# package commons resources
# configs
conf_dir=${module_dir}/configs
if [[ -d ${conf_dir} ]]; then
	cp -r ${conf_dir}/* ${conf_release_dir}
else
	logger "there is no commons resources configs in ${module_name}"
fi
logger "commons configs get ready ..."
logger ""

############################################ 打包SQL ##############################################
# sqls
sql_dir=${module_dir}/sqls
if [[ -d ${sql_dir} ]]; then
	cp -r ${sql_dir}/* ${sql_release_dir}
	logger "commons sqls get ready ..."
else
	logger "there is no SQL file to be import, skip..."
fi

############################################ 打包维表数据 ##############################################
# data files
data_dir=${module_dir}/data
if [[ -d ${data_dir} ]]; then
	logger "data_dir=${data_dir}"
	cp -r ${data_dir}/* ${data_release_dir}
	logger "commons data get ready ..."
else
	wget ${ftp_server}/data/dim-data/  -nH -m --ftp-user=ftp -nd –-cut-dirs=3  --directory-prefix=${data_release_dir} 
	logger "data_dir=${data_dir}"
	if [[ -d ${data_release_dir} ]]; then
		rm -f ${data_release_dir}/.listing
		tmp_file=""
		tar_list=($(find ${data_release_dir} -name "*.tar.gz" | sort -r))
		for dfile in ${tar_list[@]}; do
			df1=${dfile##*/}
			df1=${df1%%-*}
			#logger "dfile: ${dfile##*/}"
			if [[ "${tmp_file}" != ${df1} ]]; then
				tmp_file=${df1}
			else
				logger "to delete dim data file: ${dfile##*/}"
				rm -f ${dfile}
				tmp_file=${df1}
			fi

		done
		
		logger "commons data get ready ..."
	else
		logger "Can't connect FTP server or there is no PostgreSQL dim data, skip..."

	fi

fi

logger "package compolete, start to package deply compression file..."

############################################ 开始打包 ##############################################
cd ${cur_dir}
package_file=${cur_dir}/package/${module_name}_${module_version}.tar.gz
[[ ! -f ${cur_dir}/package ]] && mkdir -p ${cur_dir}/package
if [ -f ${package_file} ] ; then
	logger "package file(${package_file##*/}) already exists, Delete it first"
	rm -f ${package_file}
fi

cd ${release_dir%/*}
sexec "tar -zcvf ${package_file} ${release_dir##*/}"
logger "package deply file success --> ${package_file/${cur_dir}\/}"
logger "package finish"

logger "start to copy deply file to fast_deploy directory"
cd ${cur_dir}
deply_package_file=${cur_dir%/*}/fast_deploy/${package_file##*/}
if [[ -f ${deply_package_file} ]]; then
	logger "${package_file##*/} already exists in fast_deploy directory, I will delete it first"
	rm -f ${deply_package_file}
fi
cp ${package_file} ${deply_package_file}
logger "copy deply file to fast_deploy directory finish"

