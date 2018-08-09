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

TARGET_IPV4="127.0.0.1"

B="--------"
NATIVE_PING_CMD="$HOME/Dep/iputils/ping"
CONTAI_PING_CMD="/iputils/ping"

PING_ARGS="-i 0.5 -s 56" # arguments to hand to each invocation of ping
PING_WAIT_CMD="sleep 5" # command to wait for ping measurement
PAUSE_CMD="sleep 3"     # command to wait in between doing things

PING_CONTAINER_IMAGE="chrismisa/contools:ping"
PING_CONTAINER_NAME="ping-container"

# Arguments to add to trace-cmd invoke
TRACE_ARGS="-e *sendto -e *recvmsg --date"

#  # Start ping container as daemon
#  docker run --rm -itd \
#    --entrypoint=/bin/bash \
#    --name=$PING_CONTAINER_NAME \
#    $PING_CONTAINER_IMAGE

# Native procedure
echo $B Running native $B

$NATIVE_PING_CMD $PING_ARGS $TARGET_IPV4 &
PING_PID=$!
echo "  running ping with pid: $PING_PID"
$PAUSE_CMD
trace-cmd record $TRACE_ARGS -P $PING_PID \
 -o v4_native_${TARGET_IPV4}.dat &
TRACE_PID=$!
echo "  running trace-cmd record with pid: $TRACE_PID"
$PING_WAIT_CMD
kill -INT $TRACE_PID
echo "  killed trace-cmd record"
$PAUSE_CMD
kill $PING_PID
echo "  killed ping"

# docker stop $PING_CONTAINER_NAME
