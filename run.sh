#!/bin/bash

#
# Run experiment and record data
#
# The procedure for running ping is a little convoluted:
#   (1) start in background
#   (2) get it's pid
#   (3) wait a second
#   (4) start tracing it
#   (5) wait a while
#   (6) pull out the trace
#   (7) kill the ping.
#
# In this way the same procedure maybe used for the native and container run
# where step (2) in the container run is a little more involved.
#

TARGET_IPV4="10.10.1.2"

B="----------------"
NATIVE_PING_CMD="$(pwd)/iputils/ping"
CONTAINER_PING_CMD="/iputils/ping"

# Sequence of arguments to hand to each invocation of ping
declare -A PING_ARG_SEQ=(
  ["i0.5_s56"]="-D -i 0.5 -s 56" 
)

PING_WAIT_CMD="sleep 600" # command to wait for ping measurement
PAUSE_CMD="sleep 5"     # command to wait in between doing things

PING_CONTAINER_IMAGE="chrismisa/contools:ping"
PING_CONTAINER_NAME="ping-container"

# Arguments to add to trace-cmd invocations
TRACE_ARGS="-e *sendto -e *recvmsg --date"

# Argument to add to tcpdump invocations
TCPDUMP_ARGS="-i eno1d1 icmp or icmp6"

# Experiment book keeping
DATE_TAG=`date +%Y%m%d%H%M%S`
META_DATA="Metadata"

#
# Experiment Start
#

echo $B Gathering metadata $B

mkdir $DATE_TAG
cd $DATE_TAG

# Get some basic meta-data
echo "uname -a -> $(uname -a)" >> $META_DATA
echo "docker -v -> $(docker -v)" >> $META_DATA
echo "lsb_release -a -> $(lsb_release -a)" >> $META_DATA
echo "sudo lshw -> $(sudo lshw)" >> $META_DATA

# Start ping container as service
docker run --rm -itd \
  --name=$PING_CONTAINER_NAME \
  --entrypoint=/bin/bash \
  $PING_CONTAINER_IMAGE
echo $B Started $PING_CONTAINER_NAME $B

# START RUNS LOOP
for file_sfx in ${!PING_ARG_SEQ[@]}
do
  PING_ARGS=${PING_ARG_SEQ[$file_sfx]}

  # # # # # # # # # # # # # # # 
  # Native procedure
  # # # # # # # # # # # # # # # 
  echo $B Running native $B

  # Start ping
  $NATIVE_PING_CMD $PING_ARGS $TARGET_IPV4 > v4_native_${TARGET_IPV4}_${file_sfx}.ping &
  PING_PID=$!
  echo "  running ping with pid: $PING_PID"
  $PAUSE_CMD

  # Start ftrace
  trace-cmd record $TRACE_ARGS -P $PING_PID \
   -o v4_native_${TARGET_IPV4}_${file_sfx}.dat &
  TRACE_PID=$!
  echo "  running trace-cmd record with pid: $TRACE_PID"

  # Let the data collect
  $PING_WAIT_CMD

  # Stop ftrace
  kill -INT $TRACE_PID
  echo "  killed trace-cmd record"
  $PAUSE_CMD

  # Stop ping
  kill -INT $PING_PID
  echo "  killed ping"
  $PAUSE_CMD

  # # # # # # # # # # # # # # # 
  # Container procedure
  # # # # # # # # # # # # # # # 
  echo $B Running container $B

  # Start ping
  docker exec $PING_CONTAINER_NAME $CONTAINER_PING_CMD $PING_ARGS $TARGET_IPV4 > v4_container_${TARGET_IPV4}_${file_sfx}.ping &
  sleep 2
  PING_PID=`ps -e | grep ping | sed -E "s/ *([0-9]+) .*/\1/"`
  echo "  running ping with pid: $PING_PID"
  $PAUSE_CMD

  # Start ftrace
  trace-cmd record $TRACE_ARGS -P $PING_PID \
    -o v4_container_${TARGET_IPV4}_${file_sfx}.dat &
  TRACE_PID=$!
  echo "  running trace-cmd record with pid: $TRACE_PID"

  # Let the data accumulate
  $PING_WAIT_CMD

  # Stop ftrace
  kill -INT $TRACE_PID
  echo "  killed trace-cmd record"
  $PAUSE_CMD

  # Stop ping
  kill -INT $PING_PID
  echo "  killed ping"
  $PAUSE_CMD

  # Convert to canonical text forms
  echo $B Dumping to text $B
  trace-cmd report -t -i v4_native_${TARGET_IPV4}_${file_sfx}.dat > v4_native_${TARGET_IPV4}_${file_sfx}.ftrace
  trace-cmd report -t -i v4_container_${TARGET_IPV4}_${file_sfx}.dat > v4_container_${TARGET_IPV4}_${file_sfx}.ftrace

done # END RUNS LOOP

docker stop $PING_CONTAINER_NAME
echo $B Stoped $PING_CONTAINER_NAME $B

echo Done.
