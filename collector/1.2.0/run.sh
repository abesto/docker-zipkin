#!/bin/bash
if [[ -z $DB_PORT_7000_TCP_ADDR ]]; then
  echo "** ERROR: You need to link the cassandra container as db."
  exit 1
fi

SERVICE_NAME="zipkin-collector-service"
CONFIG="/zipkin/config/collector-cassandra.scala"

echo "** Starting ${SERVICE_NAME}..."
sed -i "s/localhost/${DB_PORT_7000_TCP_ADDR}/" $CONFIG
java -jar /zipkin/$SERVICE_NAME.jar -f $CONFIG
