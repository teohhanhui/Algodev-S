# Default configuration file; do not edit this file, but the file .S-config.sh
# in your home directory. The latter gets created on the very first execution
# of some benchmark script (even if only the option -h is passed to the script).

# first, a little code to to automate stuff; configuration parameters
# then follow

if [[ "$1" != "-h" && "$(id -u)" -ne "0" ]]; then
    echo "You are currently executing me as $(whoami),"
    echo "but I need root privileges (e.g., to switch"
    echo "between schedulers)."
    echo "Please run me as root."
    exit 1
fi

function find_dev_for_dir
{
    PART=$(df -P $1 | awk 'END{print $1}')
    PART=$(readlink -f $PART) # moves to /dev/dm-X in case of device mapper
    PART=$(basename $PART)

    # get physical partition if $PART is a device mapper
    if [ "$(echo $PART | egrep dm-)" != "" ] ; then
	PART=$(ls /sys/block/$PART/slaves | cut -f 1 -d " ")
    fi

    # get device from partition
    BACKING_DEV=$(basename "$(readlink -f "/sys/class/block/$PART/..")")

    if [[ "$BACKING_DEV" == "" ]]; then
	echo Block device for partition $PART unrecongnized.
	echo Try setting your target device manually in ~/.S-config.sh
	exit
    fi
}

function use_scsi_debug_dev
{
    if [[ "$(lsmod | egrep scsi_debug)" == "" ]]; then
	sudo modprobe scsi_debug ndelay=80000000 dev_size_mb=1000 max_queue=4
    fi

    BACKING_DEV=$(lsscsi | egrep scsi_debug | sed 's<\(.*\)/dev/</dev/<')
    BACKING_DEV=$(echo $BACKING_DEV | awk '{print $1}')

    if [[ ! -b ${BACKING_DEV}1 ]]; then
	echo 'start=2048, type=83' | sfdisk $BACKING_DEV
    fi

    if [[ "$(mount | egrep /mnt/scsi_debug)" == "" ]]; then
	fsck.ext4 /dev/sdb1
	if [[ $? -ne 0 ]]; then
	    mkfs.ext4 ${BACKING_DEV}1
	fi

	mkdir -p /mnt/scsi_debug
	mount ${BACKING_DEV}1 /mnt/scsi_debug
    fi
}

# BEGINNING OF CONFIGURATION PARAMETERS

# If equal to 1, tracing is enabled during each test
TRACE=0

# Size of the files to create for reading/writing, in MB.
# For random I/O with rotational devices, consider that the
# size of the files may heavily influence throughput and, in
# general, service properties
FILE_SIZE_MB=500

# portion, in 1M blocks, to read for each file, used only in fairness.sh;
# make sure it is not larger than $FILE_SIZE_MB
NUM_BLOCKS=2000

# BASE_DIR is where test files are read from or written to
if [[ "$SCSI_DEBUG" == yes ]]; then
    use_scsi_debug_dev # this will set BASE_DIR
else
    BASE_DIR=/var/lib/S # or the directory you prefer

    if [[ "$1" != "-h" && ! -d $BASE_DIR ]]; then
	mkdir $BASE_DIR
    fi
    if [[ "$1" != "-h" && ! -w $BASE_DIR ]]; then
	echo "$BASE_DIR is not writeable, reverting to /tmp/test"
	BASE_DIR=/tmp/test
	mkdir -p $BASE_DIR
    fi
    if [[ "$1" != "-h" && -d $BASE_DIR ]]; then
	find_dev_for_dir $BASE_DIR
    fi
fi

# Next parameter contains the name of the device the test files are
# on. That device is the one for which, e.g., the I/O scheduler is
# changed, if you do ask the benchmarks to select the scheduler(s) to
# use. The above code tries to detect automatically such a name, and
# puts the result in BACKING_DEV.  If automatic detection does not
# work, or is not wat you want, then just reassign the value of
# DEV. For example: DEV=sda.
DEV=$BACKING_DEV

# file names
BASE_FILE_PATH=$BASE_DIR/largefile

# The kernel-development benchmarks expect a repository in the
# following directory. In particular, they play with v4.0, v4.1 and
# v4.2, so they expect these versions to be present.
KERN_DIR=$BASE_DIR/linux.git-for_kern_dev_benchmarks
# If no repository is found in the above directory, then a repository
# is cloned therein. The source URL is stored in the following
# variable.
KERN_REMOTE=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

# NCQ queue depth, if undefined then no script will change the current value
NCQ_QUEUE_DEPTH=

# Mail-report parameters. A mail transfer agent (such as msmtp) and a mail
# client (such as mailx) must be installed to be able to send mail reports.
# The sender e-mail address will be the one configured as default in the
# mail client itself.
MAIL_REPORTS=0
MAIL_REPORTS_RECIPIENT=

if [[ "$1" != "-h" ]]; then
    # test target device
    cat /sys/block/$DEV/queue/scheduler >/dev/null 2>&1
    if [ $? -ne 0 ]; then
	echo There is something wrong with the device $DEV, which I have
	echo computed as the device on which your root directory is mounted.
	echo Try setting your target device manually in ~/.S-config.sh
	exit
    fi
fi
