import com.twitter.zipkin.builder.QueryServiceBuilder
import com.twitter.zipkin.cassandra
import com.twitter.zipkin.storage.Store

// development mode.
val keyspaceBuilder = cassandra.Keyspace.static(nodes = Set("localhost"))
val storeBuilder = Store.Builder(
  cassandra.StorageBuilder(keyspaceBuilder),
  cassandra.IndexBuilder(keyspaceBuilder),
  cassandra.AggregatesBuilder(keyspaceBuilder))

QueryServiceBuilder(storeBuilder)