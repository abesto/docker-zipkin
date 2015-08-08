FROM java:7

ADD https://dl.bintray.com/abesto/zipkin-test/io/zipkin/zipkin-collector-service/1.2.2/zipkin-collector-service-1.2.2-all.jar /zipkin/zipkin-collector-service.jar
ADD collector-cassandra.scala /zipkin/config/collector-cassandra.scala

ADD run.sh /usr/local/bin/run
ENTRYPOINT ["/usr/local/bin/run"]

EXPOSE 9410
