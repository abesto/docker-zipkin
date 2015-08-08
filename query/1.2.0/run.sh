#!/bin/bash
if [[ -z $DB_PORT_7000_TCP_ADDR ]]; then
  echo "** ERROR: You need to link the cassandra container as db."
  exit 1
fi

cd zipkin

SERVICE_NAME="zipkin-query-service"
CONFIG="/zipkin/config/query-cassandra.scala"

echo "** Starting ${SERVICE_NAME}..."
sed -i "s/localhost/${DB_PORT_7000_TCP_ADDR}/" $CONFIG
java -jar /zipkin/$SERVICE_NAME.jar -f $CONFIG
