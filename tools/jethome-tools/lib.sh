detect_partition() {
	if [[ -n "$1" ]] ; then
		local detected_partition
		detected_partition=$(fdisk -l "$1" | grep -P -A 100 "Device.+Boot.+Start.+End.+Sectors.+Size.+Id.+Type")
		local partition_line
		partition_line=$(echo "$detected_partition" | head -n2 | tail -n1)
		[[ -z "$partition_line" ]] && return 1
		partition_start=$(echo "$partition_line" | awk '{print $2}')
		[[ -z "$partition_start" ]] && return 2
		partition_size=$(echo "$partition_line" | awk '{print $4}')
		[[ -z "$partition_size" ]] && return 3
		echo "${partition_start} ${partition_size}"
	else
		return 4
	fi
}

extract_partition() {
	if [[ -n "$1" || -n "$2" || -n "$3" || -n "$4" ]] ; then
		local input_file="$1"
		local skip="$2"
		local count="$3"
		local output_file="$4"
		# 1b = 512 bytes
		dd bs=1b skip="$skip" count="$count" if="$input_file" of="$output_file" > /dev/null 2>&1 || return 1
	else
		return 2
	fi
}

