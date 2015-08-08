FROM java:7

ADD https://dl.bintray.com/abesto/zipkin-test/io/zipkin/zipkin-web/1.2.2/zipkin-web-1.2.2-all.jar /zipkin/zipkin-web.jar

ADD run.sh /usr/local/bin/run
ENTRYPOINT ["/usr/local/bin/run"]

EXPOSE 8080
