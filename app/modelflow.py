import logging
from datetime import datetime

import boto3
import mlflow
import pandas as pd
from metaflow import FlowSpec, Parameter, step
from sklearn import tree
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

from feast import FeatureStore


class ModelPipelineFlow(FlowSpec):
    """
    Model pipeline flow
    """

    data_column_list = [
        "sepal_length",
        "sepal_width",
        "petal_length",
        "petal_width",
    ]

    bucket_name = Parameter(
        "bucket_name",
        help="S3 bucket name",
        default="demo-test-bucket",
    )

    endpoint_url = Parameter(
        "endpoint_url",
        help="Minio endpoint url",
        default="http://10.244.0.26:9000",
    )

    access_key = Parameter(
        "access_key",
        help="Minio access key",
        default="test-access-key",
    )

    secret_key = Parameter(
        "secret_key",
        help="Minio secret key",
        default="test-secret-key",
    )

    @step
    def start(self):
        """
        Use the Metaflow client to retrieve the latest successful run from our
        ModelPipelineFlow and assign them as data artifacts in this flow.
        """

        # Load
        store = FeatureStore(repo_path="./app/feast/")

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

        predictions_df = store.get_historical_features(
            entity_df=entity_df,
            features=[
                "iris_data_view:class",
            ],
        ).to_df()

        X_train, X_test, y_train, y_test = train_test_split(
            training_df[self.data_column_list],
            predictions_df["class"],
            test_size=0.2,
            random_state=42,
        )

        self.X_train, self.X_test, self.y_train, self.y_test = (
            X_train,
            X_test,
            y_train,
            y_test,
        )

        self.next(self.model_training)

    @step
    def model_training(self):
        """
        Data extraction
        """

        mlflow_experiment_name = "iris_dataset"
        mlflow.set_experiment(mlflow_experiment_name)
        mlflow.sklearn.autolog()

        model = tree.DecisionTreeClassifier()

        logger.info("Beginning to train model!")
        with mlflow.start_run() as run:
            self.model = model.fit(self.X_train, self.y_train)

        logger.info("Model training complete!")
        self.run = run

        self.next(self.model_evaluation)

    @step
    def model_evaluation(self):
        """
        Model evaluation
        """

        y_pred = self.model.predict(self.X_test)

        self.test_accuracy = accuracy_score(self.y_test, y_pred)

        self.next(self.model_registry)

    @step
    def model_registry(self):
        """
        Model registry
        """

        model_uri = "runs:/{}/model".format(self.run.info.run_id)

        model_registry_information = {"registry": False, "create_deploy": False}
        if self.test_accuracy >= 0.95:
            logger.info(
                f"Model has accuracy {self.test_accuracy}, logging model for prod!"
            )
            mv = mlflow.register_model(model_uri, "iris-dataset-model")
            model_registry_information["registry"] = True
            model_registry_information["modeluri"] = "models:/{}/{}".format(
                mv.name, mv.version
            )
            self.mv = mv
            self.create_deploy = True

        self.next(self.model_upload)

    @step
    def model_upload(self):
        if self.create_deploy:
            s3 = boto3.client(
                "s3",
                endpoint_url=self.endpoint_url,
                aws_access_key_id=self.access_key,
                aws_secret_access_key=self.secret_key,
            )
            try:
                s3.create_bucket(Bucket=self.bucket_name)
            except:
                print("Bucket already exists!")

            model_path_local = self.mv.source.replace("file://", "")
            file_name = f"{model_path_local}/model.pkl"
            bucket_model_name = "iris-model.pkl"
            # Upload the file to the bucket
            s3.upload_file(file_name, self.bucket_name, bucket_model_name)

            logger.info(f"{bucket_model_name} has been uploaded to {self.bucket_name}")
        else:
            logger.info("Not logging model!")

        self.next(self.end)

    @step
    def end(self):
        """
        Print the data ETL result.
        """
        print("Finish model training pipeline.")


if __name__ == "__main__":
    ModelPipelineFlow()
