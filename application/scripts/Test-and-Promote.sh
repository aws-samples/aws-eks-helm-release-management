#!/bin/bash
echo Test-and-Promote.sh
cat output.json
export HELM_EXPERIMENTAL_OCI=1

ECR_REPO_URI=$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_DOCKER_REPO
HELM_REPO_URI=$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_HELM_REPO
echo $IMAGE_TAG
#1. read the application url from the output.json 
SERVICE_URL=$(cat output.json | jq -r '.serviceUrl')
TEST_IMAGE_TAG=$(cat output.json | jq -r '.imageTag')
TEST_DOCKER_URI=$(cat output.json | jq -r '.ecrDockerRepo')
TEST_HELM_URI=$(cat output.json | jq -r '.ecrHelmRepo')
ECR_DOCKER_IMGE_DIGEST=$(cat output.json | jq -r '.ecrDockerImageDigest')
IMAGE_TAG=$TEST_IMAGE_TAG"-rc"
echo $SERVICE_URL
echo $TEST_IMAGE_TAG
echo $TEST_DOCKER_URI
echo $TEST_HELM_URI

echo 
response=$(curl -s -o /dev/null -w "%{http_code}" $SERVICE_URL)
if [ $response != 200 ]; then
    echo "App Deployment Failed with response Code $response"
    exit 1
else 
    echo "success"
    export SERVICE_URL_OUT=$SERVICE_URL
    echo $SERVICE_URL_OUT
    # Download the Chart & Docker image tag & Update the docker tag in Values.YAML of helm Chart 
    aws ecr get-login-password | docker login --username AWS --password-stdin $TEST_DOCKER_URI
    docker pull $TEST_DOCKER_URI:$TEST_IMAGE_TAG
    # compare the checksum from exported variable before proceeding
   #1 Check for image integrity

    imageDigest=$(docker inspect $TEST_DOCKER_URI:$TEST_IMAGE_TAG | jq -r ".[].RepoDigests[]"| cut -d '@' -f 2)
    echo $imageDigest
    if [$imageDigest != $ECR_DOCKER_IMGE_DIGEST]; then 
        echo "Invalid Image Diagest "
        aws sns publish --topic-arn $SNS_TOPIC --message "Image digest din't match for image in test and Prod"
        exit 1
    fi
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URI
    
    #2 Push to Amazon ECR production repository 

    docker tag $TEST_DOCKER_URI:$TEST_IMAGE_TAG $ECR_REPO_URI:$IMAGE_TAG
    #docker images push
    docker push $ECR_REPO_URI:$IMAGE_TAG
        
    # Check with ecrDockerImageDigest & 
  
    aws ecr get-login-password --region $AWS_REGION | helm registry login --username AWS --password-stdin $TEST_HELM_URI
    echo "helm chart pull . $TEST_HELM_URI:$TEST_IMAGE_TAG"
    helm chart pull $TEST_HELM_URI:$TEST_IMAGE_TAG
        
    helm chart export $TEST_HELM_URI:$TEST_IMAGE_TAG
    cd $CODEBUILD_SRC_DIR/flask-kubernetes-helm
    # Replace the Test URI & TAGS in values.yaml
        
    #5. Push to Production ECR
    aws ecr get-login-password --region $AWS_REGION | helm registry login --username AWS --password-stdin $HELM_REPO_URI
    helm chart save . $HELM_REPO_URI:$IMAGE_TAG
    helm chart push $HELM_REPO_URI:$IMAGE_TAG
    # Wrtie the new tags to output.json
fi
cat > $CODEBUILD_SRC_DIR/output.json << EOF
{
  "imageTag":"$IMAGE_TAG",
  "ecrHelmRepo":"$HELM_REPO_URI"
}
EOF
cat $CODEBUILD_SRC_DIR/output.json