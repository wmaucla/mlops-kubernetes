from datetime import timedelta

from feast import (
    Entity,
    FeatureView,
    Field,
)
from feast.infra.offline_stores.contrib.postgres_offline_store.postgres_source import (
    PostgreSQLSource,
)

from feast.types import Float32, String

flower = Entity(name="id")


iris_postgres_source = PostgreSQLSource(
    name="iris_data_source",
    query="SELECT * FROM iris_table",
    timestamp_field="event_timestamp",
)

driver_stats_fv = FeatureView(
    name="iris_data_view",
    entities=[flower],
    ttl=timedelta(days=1),
    schema=[
        Field(name="sepal_length", dtype=Float32),
        Field(name="sepal_width", dtype=Float32),
        Field(name="petal_length", dtype=Float32),
        Field(name="petal_width", dtype=Float32),
        Field(name="class", dtype=String),
    ],
    online=True,
    source=iris_postgres_source,
)
