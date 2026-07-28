#!/bin/bash

### Deploy a development instance of EvalHub in RHOAI 3.4
### Must be logged in with cluster-admin privileges

TIMEOUT="300s"

oc patch datasciencecluster default-dsc --type=merge -p '{"spec":{"components":{"trustyai":{"managementState":"Managed"}}}}'
if ! oc wait --for condition=TrustyAIReady=true datasciencecluster/default-dsc --timeout $TIMEOUT; then
  echo "Error: Timed out after ${TIMEOUT} waiting for TrustyAI operator to become Ready." >&2
  exit 1
fi

oc project redhat-ods-applications

# This piece is NOT idempotent, it would be if I were using a YAML for deploying the database
#oc create deployment evalhubdb --replicas 0 --image registry.redhat.io/rhel9/postgresql-18
#oc set env deployment evalhubdb POSTGRESQL_USER=rhoai
#oc set env deployment evalhubdb POSTGRESQL_PASSWORD=dontdothisinprod
#oc set env deployment evalhubdb POSTGRESQL_DATABASE=evalhub
#oc set volumes deployment evalhubdb --add --name=data -t pvc --claim-name evalhubdata --claim-size=10G --mount-path /var/lib/pgsql/data
#oc expose deployment evalhubdb --port 5432
#oc scale deployment evalhubdb --replicas 1
oc apply -f evalhubdb.yaml 
if ! oc wait --for condition=Available=true deployment/evalhubdb --timeout $TIMEOUT; then
  echo "Error: Timed out after ${TIMEOUT} waiting for EvalHub's PostgreSQL database to become Available." >&2
  exit 1
fi

oc apply -f evalhub-db-credentials.yaml
oc apply -f evalhub.yaml

if ! oc wait --for condition=Ready=true evalhub/evalhub --timeout $TIMEOUT; then
  echo "Error: Timed out after ${TIMEOUT} waiting for EvalHub to become Ready." >&2
  exit 1
fi

EVALHUB_URL=https://$(oc get routes evalhub -o jsonpath='{.spec.host}')
HTTP_STATUS=$(curl -s -k -o /dev/null -w "%{http_code}" $EVALHUB_URL/api/v1/health)
if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "ERROR: EvalHub is NOT healthy." >&2
  exit 1
fi

echo "EvalHub is now ready and available."

if ! oc label namespace my-first-model evalhub.trustyai.opendatahub.io/tenant=; then
  echo "ERROR: cannot label my-first-model project for EvalHub" >&2
  exit 1
fi

echo "Project my-first-model is setup as an EvalHub tenant."
