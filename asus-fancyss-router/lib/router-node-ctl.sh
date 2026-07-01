#!/bin/sh
# router-node-ctl.sh —— 在 RT-AC86U(koolshare/fancyss)路由器上执行的节点控制逻辑
# 由本机 node-ctl 包装器通过 SSH stdin 送入执行：ssh router 'sh -s -- <cmd> [args]' < 本文件
# busybox ash 兼容。不落地安装到路由器（每次随 SSH 送入），逻辑随 git 版本化。
#
# 子命令：
#   list                 列出所有节点（id / 协议 / 名称 / 服务器），标记当前节点
#   current              当前生效节点（fss_node_current + xray.json 实连服务器 + 进程状态）
#   speed                跑原生延迟测试（覆盖所有协议），按延迟升序列出
#   switch <id>          切换到指定 id 的节点并应用，验证实连服务器 + 代理出口
#
# 关键事实（见 troubleshooting-2026-07.md）：
#   - schema2 存储：当前节点键是 fss_node_current（+ fss_node_current_identity），
#     不是旧的 ssconf_basic_node。
#   - 真相以 xray.json 的 address 为准；node-tool current-env 有缓存不可靠。

NT=/koolshare/bin/node-tool
XRAY_JSON=/koolshare/ss/xray.json
STREAM=/tmp/upload/webtest.stream

cur_id() { dbus get fss_node_current 2>/dev/null; }

xray_server() { grep -oE '"address": *"[^"]+"' "$XRAY_JSON" 2>/dev/null | head -1 | cut -d'"' -f4; }

xray_running() { ps w 2>/dev/null | grep -E "xray run" | grep -qv grep && echo yes || echo no; }

# 输出：id \t proto \t server \t name
node_rows() {
	"$NT" list --format json 2>/dev/null | tr -d '\n' | sed 's/},{/}\n{/g' | \
	while IFS= read -r line; do
		id=$(echo "$line"   | grep -oE '"id":"[^"]*"'       | head -1 | cut -d'"' -f4)
		pr=$(echo "$line"   | grep -oE '"protocol":"[^"]*"' | head -1 | cut -d'"' -f4)
		nm=$(echo "$line"   | grep -oE '"name":"[^"]*"'     | head -1 | cut -d'"' -f4)
		sv=$(echo "$line"   | grep -oE '"server":"[^"]*"'   | head -1 | cut -d'"' -f4)
		[ -n "$id" ] && printf '%s\t%s\t%s\t%s\n' "$id" "$pr" "$sv" "$nm"
	done
}

cmd_list() {
	c=$(cur_id)
	echo "ID  协议        服务器                          节点名"
	echo "--- ----------- ------------------------------- ------------------------------"
	node_rows | while IFS="$(printf '\t')" read -r id pr sv nm; do
		mark=" "; [ "$id" = "$c" ] && mark="*"
		printf '%s%-3s %-11s %-31s %s\n' "$mark" "$id" "$pr" "$sv" "$nm"
	done
	echo "(* = 当前生效节点)"
}

cmd_current() {
	c=$(cur_id)
	row=$(node_rows | awk -F'\t' -v id="$c" '$1==id{print}')
	nm=$(echo "$row" | cut -f4); pr=$(echo "$row" | cut -f2); sv=$(echo "$row" | cut -f3)
	echo "当前节点 id : ${c:-（空/未选）}"
	echo "节点名      : ${nm:-?}  [${pr}]"
	echo "订阅服务器  : ${sv:-?}"
	echo "xray 实连   : $(xray_server)"
	echo "xray 运行中 : $(xray_running)"
}

# 跑原生延迟测试，输出 id \t 延迟(ms 或 timeout/failed)
run_webtest() {
	rm -f "$STREAM" /tmp/upload/webtest.txt 2>/dev/null
	sh /koolshare/scripts/ss_webtest.sh 2 >/tmp/upload/webtest_run.log 2>&1 &
	i=0
	while [ $i -lt 24 ]; do
		sleep 5; i=$((i+1))
		grep -q "stop>stop" "$STREAM" 2>/dev/null && break
	done
	# 每个 id 取最后一次出现的值
	awk -F'>' '/^[0-9]+>/{v[$1]=$2} END{for(k in v) print k"\t"v[k]}' "$STREAM" 2>/dev/null
}

cmd_speed() {
	echo "跑原生延迟测试中（覆盖 trojan/hysteria2/anytls 等所有协议，约 30-60s）..." >&2
	run_webtest > /tmp/_wt_res 2>/dev/null   # id \t 延迟
	c=$(cur_id)
	node_rows > /tmp/_wt_rows 2>/dev/null     # id \t proto \t server \t name
	# 合并：数值延迟升序在前，timeout/failed/无数据 垫底
	awk -F'\t' -v cur="$c" '
		NR==FNR { lat[$1]=$2; next }
		{ id=$1; l=lat[id]; if(l=="") l="-";
		  if(l ~ /^[0-9]+$/) key=l+0; else key=999999;
		  printf "%06d\t%s\t%s\t%s\t%s\t%s\n", key, (id==cur?"*":" "), id, $2, l, $4 }
	' /tmp/_wt_res /tmp/_wt_rows | sort -n > /tmp/_wt_merged 2>/dev/null
	echo "延迟    当前 ID  协议        节点名"
	echo "------- ---- ---- ----------- ------------------------------"
	while IFS="$(printf '\t')" read -r key mark id pr lat nm; do
		case "$lat" in
			''|*[!0-9]*) disp="$lat"; [ "$lat" = "-" ] && disp="?" ;;
			*) disp="${lat}ms" ;;
		esac
		printf '%-7s  %s   %-3s %-11s %s\n' "$disp" "$mark" "$id" "$pr" "$nm"
	done < /tmp/_wt_merged
	rm -f /tmp/_wt_res /tmp/_wt_rows /tmp/_wt_merged 2>/dev/null
	echo "(* = 当前节点；timeout/failed = 该节点当前不可用)"
}

cmd_switch() {
	target="$1"
	[ -n "$target" ] || { echo "用法: switch <id>"; return 1; }
	j=$("$NT" list --ids "$target" --format json 2>/dev/null)
	echo "$j" | grep -q '"id"' || { echo "❌ 找不到 id=$target 的节点"; return 1; }
	name=$(echo "$j" | grep -oE '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
	ident=$(echo "$j" | grep -oE '"identity":"[^"]*"' | head -1 | cut -d'"' -f4)
	echo "切换到 id=$target 【$name】 ..."
	dbus set fss_node_current="$target"
	[ -n "$ident" ] && dbus set fss_node_current_identity="$ident"
	sh /koolshare/scripts/ss_config.sh start 2>&1 | \
		grep -iE "重启节点|运行时解析成功|出口地址|出口ip检测失败|启动完毕|失败" | head -12
	echo "--- 验证 ---"
	echo "xray 实连服务器 : $(xray_server)"
	echo "xray 运行中     : $(xray_running)"
}

ACT="$1"; shift 2>/dev/null
case "$ACT" in
	list)    cmd_list ;;
	current) cmd_current ;;
	speed)   cmd_speed ;;
	switch)  cmd_switch "$@" ;;
	*) echo "用法: $0 {list|current|speed|switch <id>}"; exit 1 ;;
esac
