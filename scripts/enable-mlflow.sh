#!/bin/bash

### Deploy a development instance of MLflow in RHOAI 3.4
### Must be logged in with cluster-admin privileges

TIMEOUT="300s"

oc patch datasciencecluster default-dsc --type merge -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Managed"}}}}'
if ! oc wait --for condition=MLflowOperatorReady=true datasciencecluster/default-dsc --timeout $TIMEOUT; then
  echo "Error: Timed out after ${TIMEOUT} waiting for MLflow operator to become Ready." >&2
  exit 1
fi
oc apply -f mlflow.yaml
if ! oc wait --for condition=Available=true mlflow/mlflow --timeout "${TIMEOUT}"; then
  echo "Error: Timed out after ${TIMEOUT} waiting for MLflow to become Available." >&2
  exit 1
fi

MLFLOW_URL=$(oc get mlflow mlflow -n redhat-ods-applications -o jsonpath='{.status.url}')
TOKEN=$(oc whoami -t 2>/dev/null)
HTTP_STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$MLFLOW_URL/health")
if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "ERROR: MLflow server is NOT healthy." >&2
  exit 1
fi

echo "MLflow is now ready and available."
