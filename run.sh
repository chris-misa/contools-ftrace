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

TARGET_IPV4="10.0.0.1"

B="----------------"
NATIVE_PING_CMD="$HOME/Dep/iputils/ping"
CONTAINER_PING_CMD="/iputils/ping"

PING_ARGS="-i 0.5 -s 56" # arguments to hand to each invocation of ping
PING_WAIT_CMD="sleep 5" # command to wait for ping measurement
PAUSE_CMD="sleep 3"     # command to wait in between doing things

PING_CONTAINER_IMAGE="chrismisa/contools:ping"
PING_CONTAINER_NAME="ping-container"

# Arguments to add to trace-cmd invocations
TRACE_ARGS="-e *sendto -e *recvmsg --date"

# Argument to add to tcpdump invocations
TCPDUMP_ARGS="-i wlp2s0 icmp or icmp6"

# Start ping container as service
docker run --rm -itd \
  --name=$PING_CONTAINER_NAME \
  --entrypoint=/bin/bash \
  $PING_CONTAINER_IMAGE
echo $B Started $PING_CONTAINER_NAME $B

# START RUNS LOOP

# # # # # # # # # # # # # # # 
# Native procedure
# # # # # # # # # # # # # # # 
echo $B Running native $B

# Start ping
$NATIVE_PING_CMD $PING_ARGS $TARGET_IPV4 > v4_native_${TARGET_IPV4}.ping &
PING_PID=$!
echo "  running ping with pid: $PING_PID"
$PAUSE_CMD

# Start tcpdump
tcpdump -w v4_native_${TARGET_IPV4}.pcap $TCPDUMP_ARGS &
TCPDUMP_PID=$!
echo "  running tcpdump with pid: $TCPDUMP_PID"
$PAUSE_CMD

# Start ftrace
trace-cmd record $TRACE_ARGS -P $PING_PID \
 -o v4_native_${TARGET_IPV4}.dat &
TRACE_PID=$!
echo "  running trace-cmd record with pid: $TRACE_PID"

# Let the data collect
$PING_WAIT_CMD

# Stop ftrace
kill -INT $TRACE_PID
echo "  killed trace-cmd record"
$PAUSE_CMD

# Stop tcpdump
kill -INT $TCPDUMP_PID
echo "  killed tcpdump"
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
docker exec $PING_CONTAINER_NAME $CONTAINER_PING_CMD $PING_ARGS $TARGET_IPV4 > v4_container_${TARGET_IPV4}.ping &
sleep 2
PING_PID=`ps -e | grep ping | sed -E "s/ *([0-9]+) .*/\1/"`
echo "  running ping with pid: $PING_PID"
$PAUSE_CMD

# Start tcpdump
tcpdump -w v4_container_${TARGET_IPV4}.pcap $TCPDUMP_ARGS &
TCPDUMP_PID=$!
echo "  running tcpdump with pid: $TCPDUMP_PID"
$PAUSE_CMD

# Start ftrace
trace-cmd record $TRACE_ARGS -P $PING_PID \
  -o v4_container_${TARGET_IPV4}.dat &
TRACE_PID=$!
echo "  running trace-cmd record with pid: $TRACE_PID"

# Let the data accumulate
$PING_WAIT_CMD

# Stop ftrace
kill -INT $TRACE_PID
echo "  killed trace-cmd record"
$PAUSE_CMD

# Stop tcpdump
kill -INT $TCPDUMP_PID
echo "  killed tcpdump"
$PAUSE_CMD

# Stop ping
kill -INT $PING_PID
echo "  killed ping"
$PAUSE_CMD

# END RUNS LOOP

docker stop $PING_CONTAINER_NAME
echo $B Stoped $PING_CONTAINER_NAME $B

echo Done.
