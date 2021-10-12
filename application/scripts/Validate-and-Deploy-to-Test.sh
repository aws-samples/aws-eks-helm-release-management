#!/bin/bash
echo Validate-and-Deploy-to-Test.sh

export ECR_REPO_URI=$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_DOCKER_REPO
export NAMESPACE=flask
export HELM_EXPERIMENTAL_OCI=1


HELM_REPO_URI=$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_HELM_REPO
#Steps To Perform 
# 1. Read the output.json Value of Helm Chart TAG  & Docker Image 
export IMAGE_TAG=$(cat output.json | jq -r '.imageTag')
echo $IMAGE_TAG
aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REPO_URI
findings=$(aws ecr describe-image-scan-findings --repository-name "$ECR_DOCKER_REPO" --image-id imageTag="$IMAGE_TAG" --query "{scanResult: imageScanFindings.findingSeverityCounts,imageDigest : imageId.imageDigest}")
echo $findings
Critical=$(echo $findings | jq '.scanResult.CRITICAL // 0 | tonumber')
echo $Critical
High=$(echo $findings | jq '.scanResult.HIGH // 0 | tonumber')
echo $High
export imageDigest=$(echo $findings | jq '.imageDigest')
echo $imageDigest
# 3. If ECR SCAN is not Good then Download Helm CHART from ECR REPO 
if [ $Critical -gt 0 ] || [ $High -gt 0 ]; then
    # echo "Vulnerability found .Add Failed Tag" $imageDigest
    # if Critical & High Vulnerability mark tag as Failed.
    FAILED_TAG='ecrscan-failed-'$(date '+%s')
    MANIFEST=$(aws ecr batch-get-image --repository-name "$ECR_DOCKER_REPO" --image-ids imageTag="$IMAGE_TAG" --query 'images[].imageManifest' --output text)
    aws ecr put-image --repository-name "$ECR_DOCKER_REPO" --image-tag $FAILED_TAG --image-manifest "$MANIFEST"
    echo "Sending ECR SCAN FAILURE SNS Notification "
    echo "Image Validation Failed due to" $High "High Vulenerabilities Found or $Critical Crital Vulenerabilites"
    aws sns publish --topic-arn $SNS_TOPIC --message "Scan failed at Validate and Deploy to Test"
    exit 1
else

    aws eks update-kubeconfig --name $EKS_CLUSTERNAME --region $AWS_REGION --role-arn $EKS_CLUSTERROLE_ARN
# 5. Execute the helm upgrade --install pythonflask flask-kubernetes-helm -n flask
    kubectl get ns $NAMESPACE
    if [ $? -ne 0 ]; then  #not eual check    kubectl create ns $NAMESPACE
        kubectl create ns $NAMESPACE
    fi
    cd $CODEBUILD_SRC_DIR
    echo "Execute the helm upgrade --install pythonflask flask-kubernetes-helm -n flask"
    aws ecr get-login-password --region $AWS_REGION | helm registry login --username AWS --password-stdin $HELM_REPO_URI
    echo "helm chart pull $HELM_REPO_URI:$IMAGE_TAG"
    helm chart pull $HELM_REPO_URI:$IMAGE_TAG
    helm chart export $HELM_REPO_URI:$IMAGE_TAG
   # substitute values in chart
    cd $CODEBUILD_SRC_DIR/flask-kubernetes-helm
    envsubst < values_template.yaml > values.yaml
    #cat values_template.yaml > values.yaml
    cat values.yaml
    
    helmRevision=$(helm history --max 1 pythonflask -n $NAMESPACE -o json | jq -re ".[0].revision")
    echo $helmRevision
    helm upgrade --install -n $NAMESPACE pythonflask .
    
   
    cd $CODEBUILD_SRC_DIR
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="flask-kubernetes-helm" -n $NAMESPACE  
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n $NAMESPACE   
  
    chmod +x scripts/ValidateApp.sh
    ./scripts/ValidateApp.sh pythonflask-flask-kubernetes-helm
    SERVICE_URL=$(kubectl get svc --namespace flask pythonflask-flask-kubernetes-helm -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

    response=$(curl -s -o /dev/null -w "%{http_code}" $SERVICE_URL)
    if [ $response != 200 ]; then
        echo "App Is not Running"
        IsRollBack=1
        helm rollback pythonflask $helmRevision -n $NAMESPACE
        echo "send the rollback ON SNS topic"
        aws sns publish --topic-arn $SNS_TOPIC --message "Production Rollback"
        exit 1
    else
        IsRollBack=0
        echo "send the success ON SNS topic"
        aws sns publish --topic-arn $SNS_TOPIC --message "Production successful"
    fi


# If Successfull then Then Right the output url to output.json.
cat > $CODEBUILD_SRC_DIR/output.json << EOF
{
  "imageTag": "$IMAGE_TAG",
  "serviceUrl":"http://$SERVICE_URL",
  "ecrDockerRepo":"$ECR_REPO_URI",
  "ecrDockerImageDigest":$imageDigest,
  "ecrHelmRepo":"$HELM_REPO_URI"
}
EOF


fi

