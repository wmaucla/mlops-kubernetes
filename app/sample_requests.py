from collections import Counter

import requests

url = "http://localhost:8080/v2/models/experiment-example/infer"

headers = {
    "Content-Type": "application/json",
    "seldon-model": "experiment-example.experiment",
}

data = {
    "inputs": [
        {"name": "predict", "shape": [1, 4], "datatype": "FP32", "data": [[1, 2, 3, 4]]}
    ]
}

counter_dict = Counter()
sample_req_count = 60

for i in range(0, sample_req_count):
    response = requests.post(url, json=data, headers=headers)

    if response.status_code == 200:
        model_name = response.json()["model_name"]
        counter_dict[model_name] += 1

    else:
        print("Request failed with status code:", response.status_code)
        print("Response:", response.text)

print(counter_dict, f"example simulation of {sample_req_count} requests")
