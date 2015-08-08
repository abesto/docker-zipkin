FROM java:7

ADD https://dl.bintray.com/abesto/zipkin-test/io/zipkin/zipkin-query-service/1.2.2/zipkin-query-service-1.2.2-all.jar /zipkin/zipkin-query-service.jar
ADD query-cassandra.scala /zipkin/config/query-cassandra.scala

ADD run.sh /usr/local/bin/run
ENTRYPOINT ["/usr/local/bin/run"]

EXPOSE 9411
