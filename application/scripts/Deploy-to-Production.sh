#!/bin/bash
echo Deploy-to-Production.sh
export HELM_EXPERIMENTAL_OCI=1
export NAMESPACE=flask-prod
HELM_REPO_URI=$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_HELM_REPO
export ECR_REPO_URI=$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_DOCKER_REPO
#1. Read Production helm chart tag from output.jsom 
HELM_IMAGE_TAG=$(cat output.json | jq -r '.imageTag')
#HELM_REPO_URI=$(cat output.json | jq -r '.ecrHelmRepo')
export IMAGE_TAG=$HELM_IMAGE_TAG
#2. download helm chart from production Repo 
echo "aws eks update-kubeconfig --name $EKS_CLUSTERNAME --region $AWS_REGION --role-arn $EKS_CLUSTERROLE_ARN"
aws eks update-kubeconfig --name $EKS_CLUSTERNAME --region $AWS_REGION --role-arn $EKS_CLUSTERROLE_ARN
echo "helm chart pull $HELM_REPO_URI:$HELM_IMAGE_TAG"
aws ecr get-login-password --region $AWS_REGION | helm registry login --username AWS --password-stdin $HELM_REPO_URI
helm chart pull $HELM_REPO_URI:$HELM_IMAGE_TAG
helm chart export $HELM_REPO_URI:$HELM_IMAGE_TAG

#Failing the Image
#export HELM_IMAGE_TAG="TestitNow"
#export IMAGE_TAG="TestitNow"
cd $CODEBUILD_SRC_DIR/flask-kubernetes-helm
envsubst < values_template.yaml > values.yaml
cat values.yaml
#3. Deploy to Production EKS in Existing Namespace.
kubectl get ns $NAMESPACE
if [ $? -ne 0 ]; then  #not eual check    kubectl create ns $NAMESPACE
    kubectl create ns $NAMESPACE
fi
helmRevision=$(helm history --max 1 pythonflaskprod -n $NAMESPACE -o json | jq -re ".[0].revision")
echo $helmRevision
helm upgrade --install -n $NAMESPACE pythonflaskprod .
cd $CODEBUILD_SRC_DIR
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="flask-kubernetes-helm" -n $NAMESPACE  
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n $NAMESPACE   

chmod +x scripts/ValidateApp.sh 
./scripts/ValidateApp.sh 'pythonflaskprod-flask-kubernetes-helm'
SERVICE_URL=$(kubectl get svc --namespace $NAMESPACE pythonflaskprod-flask-kubernetes-helm -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $SERVICE_URL
#4. Check Pod came up successful If Failes Add Step to rollback and send result on SNS topic 

IsRollBack=0
response=$(curl -s -o /dev/null -w "%{http_code}" $SERVICE_URL)
#5. curl the application url Check the status If not responding fail the stage Rollback to Previous stage
if [ $response != 200 ]; then
    echo "App Is not Running"
    IsRollBack=1
    helm rollback pythonflaskprod $helmRevision -n $NAMESPACE
    echo "send the rollback ON SNS topic"
    aws sns publish --topic-arn $SNS_TOPIC --message "Production Rollback"
    exit 1
else
    IsRollBack=0
    echo "send the success ON SNS topic"
    aws sns publish --topic-arn $SNS_TOPIC --message "Production successful"
fi



