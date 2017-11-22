#!/bin/bash
#

inventory="playbook/inventory"
ansible_run="ansible controller -i ${inventory} -m shell -a"
playbook_run="ansible-playbook -i ${inventory}"

usage () {
	local script="${0##*/}"

	while read -r ; do echo "${REPLY}" ; done <<-EOF
		Usage: ${script} [OPTION]
		Node management

		Options:
		Mandatory arguments to long options are mandatory for short options too.
			-h, --help               Display this help and exit
			-t object-types          The object types, supported types [node, network, osimage]
			-r object-name           The object name of remove
		Examples:
		  1. To deploy node:
		  	${script} or ${script} -t node
		  2. To create network:
		  	${script} -t network
		  3. To remove a existing network:
		  	${script} -t network -r netname
		  4. To create os image:
		  	${script} -t osimage
		  5. To remove a existing os image:
		  	${script} -t osimage -r osimagename	
	EOF
}

#
# warn_if_bad		Put out warning message(s) if $1 has bad RC.
#
#	$1	0 (pass) or non-zero (fail).
#	$2+	Remaining arguments printed only if the $1 is non-zero.
#
#	Incoming $1 is returned unless it is 0
#
warn_if_bad() {
	local -i rc="$1"
	local script="${0##*/}"

	# Ignore if no problems
	[ "${rc}" -eq "0" ] && return 0

	# Broken
	shift
	echo "${script}: $@" >&2
	return "${rc}"
}

#
# exit_if_bad		Put out error message(s) if $1 has bad RC.
#
#	$1	0 (pass) or non-zero (fail).
#	$2+	Remaining arguments printed only if the $1 is non-zero.
#
#               Exits with 1 unless $1 is 0
#
exit_if_bad() {
	warn_if_bad "$@" || exit 1
	return 0
}

show_progress_meters () {
	[[ -t 2 ]] || return 0
	# Show the progress meters
	(
		declare -i length=0
		while :
		do
			for bar in \
				"...... " \
				".o..o. " \
				"oOooOo " \
				"OoUUoO " \
				"ooUUoo " \
				"oOooOo " \
				"Oo..oO " \
				"o....o "	
			do
				msg="${bar}"
				for (( i = 0; i < length; ++i ))
				do
					echo -ne "\b"
				done
				length=${#msg}
				echo -n "${msg}"

				sleep 0.1 2>/dev/null || sleep 1
				kill -0 "$$" >/dev/null 2>&1 || break 2
			done
		done
	) >&2 &
	PROGRESS_METERS="$!"
	disown "${PROGRESS_METERS}"
}

stop_progress_meters () {
	if [[ -t 2 ]]
	then
		kill "${PROGRESS_METERS}" >/dev/null 2>&1
		echo -ne "\b\b\b\b\b\b\b" >&2
	fi
	echo -n "...... "
}

_select_widget () {
	declare -a list=($1)
	select selected in ${list[@]}
	do
		if [[ "X$selected" != "X" ]]; then
			break
		else
			echo "Selected is not existing, choice a existing index."
		fi
	done
	IFS=" "
}

_read_input () {
	while :
	do
		echo -n $1": "
		read input
		if [[ -f $input ]]; then
			break
		else
			echo "File '$input' does not existing. Type in a correct file path."
		fi
	done
}

_get_interface () {
	$ansible_run '
	sys_net="/sys/class/net"
	nets=""
	for net in $(ls $sys_net)
	do
		if [[ -d ${sys_net}/${net}/device ]]; then
			netdetail=$(ifconfig $net | grep inet | grep -v inet6 | sed "s/^[ \t]*//g")
			nets="interface $net $netdetail#$nets"
		fi
	done
	echo $nets
	' | sed '1d'
}

create_osimage () {
	local play="playbook/osimages.yml"
	local playbook_vars="playbook/roles/osimages/vars/main.yml"
	_read_input "Input osdistro path"
	echo ""
  cat > $playbook_vars <<EOF
---

osdistros:
  - $input
EOF

	$playbook_run $play -t "create"
}

remove_osimage () {
	local play="playbook/osimages.yml"
	$playbook_run $play -t "remove" --extra-vars "osimagename=${REMOVE_OBJECT_NAME}"
}

create_network () {
	local playbook_vars="playbook/roles/networks/vars/main.yml"
	local play="playbook/networks.yml"
	_read_input "Input network defination file path"
	cat $input > $playbook_vars
	$playbook_run $play -t "create"
}

remove_network () {
	local play="playbook/network.yml"
	$playbook_run $play -t "remove" --extra-vars "netname=${REMOVE_OBJECT_NAME}"
}

defing_provision_tmpl () {
	local playbook_vars="playbook/roles/provisioning/vars/main.yml"
	# local networks=$($ansible_run '/opt/xcat/bin/lsdef -t network' | sed '1d' | cut -d ' ' -f 1)
	local osimages=$($ansible_run '/opt/xcat/bin/lsdef -t osimage' | sed '1d' | cut -d ' ' -f 1)
	local interfaces=$(_get_interface)

	[[ "X$osimages" == "X" ]] && echo "No availiavle os image, create an os image before deploy node first." && exit 1
	# [[ "X$networks" == "X" ]] && echo "No availiavle network defination, create a network before deploy node first." && exit 1
	
	PS3="Enter your selection: "
	echo "Select an os image for the provisioning from the following options:"
	echo "-------------------------------------------------------------------"
	_select_widget "$osimages"
	echo "osimage: $selected" > $playbook_vars

	# PS3="Select Provision Network: "
	# _select_widget "$networks"
	# echo "network: $selected" >> $playbook_vars
	echo
	echo "Select a network interface for the provisioning from the following options:"
	echo "---------------------------------------------------------------------------"
	IFS="#"
	_select_widget "$interfaces"
	echo "nic: $selected" >> $playbook_vars
}


import_node () {
	local playbook_vars="playbook/roles/provisioning/vars/main.yml"
	echo
	echo "To provisioning node, a node information file should be prepare"
	echo "---------------------------------------------------------------"
	_read_input "Enter the full path of file"
	cat $input >> $playbook_vars
}

auto_discover_node () {
	local playbook_vars="playbook/roles/provisioning/vars/main.yml"
	echo "auto_discover: true" >> $playbook_vars	
}

discover_node () {
	local play="playbook/provisioning.yml"
	$playbook_run $play >> $LOGFILE
}

deploy_node() {
	while read -r ; do echo "${REPLY}" ; done <<-EOF

	Prepare node info for provisioning, following prepare is needed 
	before node provisioning:
	====================================================================

	EOF

	defing_provision_tmpl
	import_node
	show_progress_meters
	discover_node
	stop_progress_meters

	while read -r ; do echo "${REPLY}" ; done <<-EOF

	Node prepare has been done  
	====================================================================
	The provisioning process should be started, if it's not start, you
	need manual power the node.
	EOF
}
LOGFILE="/var/log/nodemanagement.log"
OBJECT_TYPE=""
REMOVE_OBJECT_NAME=""
while [ "$#" -gt "0" ]
do
	case "$1" in
	"-h"|"--help")
		usage
		exit 0
		;;
	"-t")
		shift
		OBJECT_TYPE="$1"
		;;
	"-r")
		shift
		REMOVE_OBJECT_NAME="$1"
		;;
	*)
		warn_if_bad 1 "invalid option -- \`$1'"
		exit_if_bad 1 "Try \`$0 --help' for more information"
		;;
	esac
	shift
done

if [[ "X$REMOVE_OBJECT_NAME" != "X" ]]; then
	if [[ "$OBJECT_TYPE" == "network" ]]; then
		remove_network
	elif [[ "$OBJECT_TYPE" == "osimage" ]]; then
		remove_osimage
	fi
else
	if [[ "$OBJECT_TYPE" == "network" ]]; then
		create_network
	elif [[ "$OBJECT_TYPE" == "osimage" ]]; then
		create_osimage
	else
		deploy_node
	fi
fi



