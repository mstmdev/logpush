#!/bin/sh

#日志文件路径
log_name="access.txt"
#日志文件行数
log_count=`wc -l $log_name`
#redis命令行工具
redis_cli="redis-cli"
#redis主机地址
redis_host="127.0.0.1"
#redis端口地址
redis_port="6379"
#redis 默认db
redis_db="0"
#推送的redis队列的key
redis_push_key="nginx_push_list_$(date +%Y-%m-%d)"
# 开始读取的行号
start_row_num=0
#记录读取历史进度的文件
logpush_history_file="logpush_history"

#消耗队列
#echo `redis-cli -h $redis_host -p $redis_port lpop $redis_push_key`

# 1.查询redis-cli是否存在
if [ -f "$redis_cli" ];then
echo -e  "查找redis-cli --> \033[32msuccess\033[0m"
else
echo -e "查找redis-cli --> \033[33mfailed\033[0m"
echo "开始尝试在当前目录查找redis-cli"

$redis_cli="./"+$redis_cli

if [ -f $redis_cli ];then
echo -e "在当前目录下查找redis-cli --> \033[32msuccess\033[0m"
else
echo -e "在当前目录下查找redis-cli --> \033[31mfailed\033[0m"
echo "你可以在以下地址下载编译redis-cli : https://redis.io/download"
exit
fi 


fi 

# 2.检查redis连通性
ping_result=`redis-cli -h $redis_host -p $redis_port -n $redis_db PING`
if [ $ping_result != "PONG" ];then
echo "redis 连接失败"
echo $ping_result
exit
else
echo -e  "redis 连接测试 \033[35m$redis_host:$redis_port db:$redis_db\033[0m --> \033[32msuccess\033[0m "
fi

echo -e "当前推送的redis key为:  \033[35m$redis_push_key\033[0m "

#for line in `cat $log_name`;do echo $line;done

if [ -f "$logpush_history_file" ];then
start_row_num=`cat $logpush_history_file`
echo -e  "上次读取到第\033[32m$start_row_num\033[0m行，开始继续处理"
else
echo 0 > $logpush_history_file
start_row_num=$[0]
fi


# 3.循环遍历每一行数据
current_row=0

# || [[ -n ${line} ]]; 用于兼容无法读取最后一行
while read line || [[ -n ${line} ]];
do
echo "-----------------------"

# 如果当前行数小于等于历史行号，则忽略
current_row=`expr  $current_row + 1`
#echo "current_row=$current_row"
#echo "start_row_num=$start_row_num"
if [ $current_row -le $start_row_num ];then
echo "当前行已经读取过，忽略  行号为$current_row  历史读取行号为$start_row_num"
continue 
fi

# 4.提取有效数据，组成新的数据结构
############type 1 start################
# 因为使用了管道 导致不能改变外部的变量 暂时弃用
#echo $line | awk -F " " '{print $1,$3,$8}' | while read from_ip target_ip access_url
#do
############type 1 end################

############type 2 start################
#使用for替代管道处理
from_ip=""
target_ip=""
access_url=""
params=`echo $line | awk -F " " '{print $1,$3,$8}' `
#echo " params  $params"
p_index=0
for p in $params;
do
if [ $p_index -eq 0 ];then
from_ip=$p
elif [ $p_index -eq 1 ];then
target_ip=$p
elif [ $p_index -eq 2 ];then
access_url=$p
fi
p_index=`expr $p_index + 1`
done
############type 2 end################


	data_from_ip=$from_ip  
	data_target_ip=$target_ip 
	data_access_url=$access_url
	
	data_pid=""
	data_account=""
	data_liveid=""
	data_uid=""

	cols=`echo $data_access_url | awk -F "?" '{print $2 ;}'|awk -F "&" '{for(i=1;i<=NF;i++){print $i ;}}'`
	#echo $cols
	#echo "######################"

	for item in $cols;
	do

		# todo  新增字段修改此处和模板 redis_push_template
		#字段匹配
		if [[ $item == pid=* ]];then
		data_pid=`echo ${item##*=}`;
		elif [[ $item == uid=* ]];then
		data_uid=`echo ${item##*=}`;
		fi
	done	


	#redis队列推送模板
	redis_push_template="{\"from_ip\":\"$data_from_ip\",\"target_ip\":\"$data_target_ip\",\"pid\":\"$data_pid\",\"account\":\"$data_account\",\"liveid\":\"$data_liveid\",\"uid\":\"$data_uid\"}"

	push_data=`echo $redis_push_template`
	echo "推送数据：$push_data"

	# 5.推送到redis队列中
	push_result=`redis-cli -h $redis_host -p $redis_port -n $redis_db lpush $redis_push_key "$push_data" `
	start_row_num=`expr $start_row_num + 1`
	echo "start_row_num=$start_row_num "
	echo "推送结果：$push_result"

# type1 的done
# done

done <$log_name

echo $start_row_num > $logpush_history_file
echo "当前读取的行号：$start_row_num "
exit 0

