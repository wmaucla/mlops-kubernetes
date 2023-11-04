import logging
import subprocess
from datetime import datetime

import pandas as pd
import psycopg2
from metaflow import Flow, FlowSpec, Parameter, get_metadata, step
from psycopg2 import sql
from sklearn import datasets
from sklearn.preprocessing import minmax_scale


from feast import FeatureStore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()


class DataPipelineFlow(FlowSpec):
    """
    Creates an end-to-end data pipeline process in preparation for model training.

    Parameters:
        dataset_name (str): Dataset used for training
        database_creds (dict): Database connection parameters.
    """

    dataset_name = Parameter(
        "dataset_name",
        help="Training dataset name",
        default="iris",
    )

    database_creds = Parameter(
        "database_creds",
        help="Postgres DB credentials",
        default={
            "database": "mydb",
            "user": "postgres",
            "password": "1ki6EsXo4s",
            "host": "10.244.0.3",
            "port": "5432",
        },
    )

    @step
    def start(self):
        """
        Use the Metaflow client to retrieve the latest successful run from our
        DataPipelineFlow and assign them as data artifacts in this flow.
        """
        logger.info("Start data pipeline.")

        # Print metadata provider
        logger.info("Using metadata provider: %s", get_metadata())

        # Load the analysis from the Flow.
        run = Flow("DataPipelineFlow").latest_successful_run
        logger.info("Using analysis from '%s'", str(run))

        self.next(self.create_db)

    @step
    def create_db(self):
        logger.info("Start DB creation.")
        db = self.database_creds
        new_db_name = db["database"]

        del db["database"]  # db doesn't exist yet

        conn = psycopg2.connect(**db)
        cur = conn.cursor()
        conn.autocommit = True
        cur.execute(f"DROP DATABASE IF EXISTS {new_db_name}")
        cur.execute(f"create database {new_db_name}")

        self.next(self.create_table)

    @step
    def create_table(self):
        """
        In lieu of providing a live data stream, simulates the idea of creating historical, fake
        data for training purposes. Here setups up a postgres instance and takes data from the iris
        dataset.
        """
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(**self.database_creds)
        cur = conn.cursor()

        # Create a table for the Iris dataset
        create_table_query = """
            CREATE TABLE IF NOT EXISTS iris_table (
                id SERIAL PRIMARY KEY,
                sepal_length real,
                sepal_width real,
                petal_length real,
                petal_width real,
                class varchar(50),
                event_timestamp TIMESTAMP
            );
        """
        logger.info("Executing create table query!")
        cur.execute(create_table_query)
        conn.commit()

        self.next(self.data_extraction)

    @step
    def data_extraction(self):
        """
        Pull data from iris and do some simple data preprocessing/transformation steps
        """

        iris_data = datasets.load_iris()

        df = pd.DataFrame(data=iris_data.data, columns=iris_data.feature_names)
        df["class"] = iris_data.target
        self.data_column_list = [
            "sepal_length",
            "sepal_width",
            "petal_length",
            "petal_width",
        ]

        x_data = df[iris_data.feature_names]
        x_data = minmax_scale(x_data, feature_range=(0, 1), axis=0, copy=True)
        y_data = list(pd.factorize(df["class"])[0])

        x_data = pd.DataFrame(
            x_data,
            columns=self.data_column_list,
        )
        y_data = pd.DataFrame(y_data, columns=["class"])
        data = pd.concat([x_data, y_data], axis=1)

        self.data = data
        self.next(self.data_upload)

    @step
    def data_upload(self):
        """
        Simulate writing data to the offline store. Iterate through the dataframe and upload data
        to the database.
        """
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(**self.database_creds)
        cur = conn.cursor()

        logger.info("Uploading data to database!")
        for _, row in self.data.iterrows():
            # insert_query = """
            #         INSERT INTO iris_table (sepal_length, sepal_width, petal_length, petal_width, class,
            #         event_timestamp)
            #         VALUES (%s, %s, %s, %s, %s, %s);
            #     """
            insert_query = f"""
                INSERT INTO iris_table ({", ".join(self.data_column_list + ["class", "event_timestamp"])})
                VALUES ({", ".join(["%s"] * (len(self.data_column_list) + 2))});
            """
            cur.execute(
                insert_query,
                (
                    row[self.data_column_list[0]],
                    row[self.data_column_list[1]],
                    row[self.data_column_list[2]],
                    row[self.data_column_list[3]],
                    row["class"],
                    datetime(2023, 10, 1, 0, 0, 0),
                ),
            )

        conn.commit()

        # Close the database connection
        conn.close()
        logger.info("Upload successful!")

        self.next(self.apply_data)

    @step
    def apply_data(self):
        """
        Once training data written to database, set up feast infrastructure. Connect to the feast registry
        and write metadata about features being used.
        """
        logger.info("Feast apply!")
        subprocess.run(["feast", "apply"], cwd="./app/feast")
        self.next(self.fetch_data)

    @step
    def fetch_data(self):
        """
        Verify for testing purposes that we can pull data from offline store.
        """
        store = FeatureStore(repo_path="./app/feast")
        entity_df = pd.DataFrame.from_dict(
            {
                "id": [i + 1 for i in range(150)],
                "event_timestamp": [datetime(2023, 10, 1, 0, 0, 0) for _ in range(150)],
            }
        )

        training_df = store.get_historical_features(
            entity_df=entity_df,
            features=[f"iris_data_view:{x}" for x in self.data_column_list],
        ).to_df()

        assert len(training_df) == 150  # assert that data was uploaded successfully
        logger.info("Verified that data was uploaded correctly!")

        self.next(self.end)

    @step
    def end(self):
        """
        Log that the ETL has finished.
        """
        logger.info("Data ETL pipeline completed.")


if __name__ == "__main__":
    DataPipelineFlow()
