#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git na311.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

TASKS_DEV_PROJECT_NAME="$GUID-tasks-dev"
TASKS_PROD_PROJECT_NAME="$GUID-tasks-prod"
JENKINS_PROJECT_NAME="$GUID-jenkins"

# Deploy Persistent Jenkins
echo "** Deploy Jenkins App **"
oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi --param DISABLE_ADMINISTRATIVE_MONITORS=true -n $JENKINS_PROJECT_NAME

# Adjust Jenkins Resource Resource
echo "** Adjust Jenkins Resource Resource **"
oc set resources dc jenkins --limits=memory=2Gi,cpu=2 --requests=memory=1Gi,cpu=500m -n $JENKINS_PROJECT_NAME
oc label dc jenkins app=jenkins --overwrite -n $JENKINS_PROJECT_NAME

# Configure Jenkins Service Accounts
echo "** Configure Jenkins Service Accounts **"
oc policy add-role-to-group edit system:serviceaccounts:$JENKINS_PROJECT_NAME -n $TASKS_DEV_PROJECT_NAME
oc policy add-role-to-group edit system:serviceaccounts:$JENKINS_PROJECT_NAME -n $TASKS_PROD_PROJECT_NAME
oc policy add-role-to-group system:image-puller system:serviceaccounts:$TASKS_PROD_PROJECT_NAME -n $TASKS_DEV_PROJECT_NAME
oc policy add-role-to-user edit system:serviceaccount:$JENKINS_PROJECT_NAME:jenkins -n $TASKS_DEV_PROJECT_NAME
oc policy add-role-to-user edit system:serviceaccount:$JENKINS_PROJECT_NAME:jenkins -n $TASKS_PROD_PROJECT_NAME
oc policy add-role-to-user edit system:serviceaccount:gpte-jenkins:jenkins -n $JENKINS_PROJECT_NAME
oc policy add-role-to-user edit system:serviceaccount:gpte-jenkins:jenkins -n $TASKS_DEV_PROJECT_NAME
oc policy add-role-to-user edit system:serviceaccount:gpte-jenkins:jenkins -n $TASKS_PROD_PROJECT_NAME

# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
echo "** Creating Pipeline Build Config **"
PIPELINE_STRATEGY="pipeline"
PIPELINE_CONTEXT_PATH="openshift-tasks"
PIPELINE_NAME="tasks-pipeline"
echo "Creating Pipeline with repo ${REPO} strategy ${PIPELINE_STRATEGY} and context-dir ${PIPELINE_CONTEXT_PATH} with name ${PIPELINE_NAME} on $JENKINS_PROJECT_NAME"
oc new-build ${REPO} --strategy=${PIPELINE_STRATEGY} --context-dir=${PIPELINE_CONTEXT_PATH} --name=${PIPELINE_NAME} -n $JENKINS_PROJECT_NAME

# Create custom agent container image with skopeo
echo "** Creating Skopeo Jenkins Agent **"
oc new-build -D $'FROM docker.io/openshift/jenkins-agent-maven-35-centos7:v3.11\n
      USER root\nRUN yum -y install skopeo && yum clean all\n
      USER 1001' --name=jenkins-agent-appdev -n $JENKINS_PROJECT_NAME

# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done
