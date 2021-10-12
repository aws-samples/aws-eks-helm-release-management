#!/bin/bash
echo Build-and-Containerize.sh
FLASK_APP=flask-app
HELM_TEMPLATE=flask-kubernetes-helm
export IMAGE_TAG="1.0."$CODEBUILD_RESOLVED_SOURCE_VERSION
export ECR_REPO_URI=$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_DOCKER_REPO
HELM_REPO_URI=$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_HELM_REPO
export HELM_EXPERIMENTAL_OCI=1
echo $IMAGE_TAG
echo $AWS_REGION
echo $AWS_DEFAULT_REGION
pip install awscli --upgrade --user
aws codeartifact login --tool pip --domain $ARTIFACT_DOMAIN --domain-owner $ACCOUNTID --repository $ARTIFACT_REPOSITORY

# Best practice is wait for CodeGuru to finish the code review, but it takes too long for the lab, therefore skipping.
# folderName=$(git diff-tree --no-commit-id --name-only -r $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -d '/' -f 1)                         
# echo $folderName
# if [[ " ${folderName[*]} " == *"flask-app"* ]] || [ -z "$folderName" ] ; then 
#   chmod +x scripts/codeScan.sh
#   . ./scripts/codeScan.sh
# fi

cd $CODEBUILD_SRC_DIR/$FLASK_APP
aws ecr get-login-password  | docker login --username AWS --password-stdin $ECR_REPO_URI
echo "image doesn't exist hence pushing"; 
docker build -t $ECR_REPO_URI:$IMAGE_TAG .
docker images
   
docker push $ECR_REPO_URI:$IMAGE_TAG
    
    
cd $CODEBUILD_SRC_DIR/$HELM_TEMPLATE
    
  
aws ecr get-login-password | helm registry login --username AWS --password-stdin $HELM_REPO_URI
helm chart save . $HELM_REPO_URI:$IMAGE_TAG
helm chart push $HELM_REPO_URI:$IMAGE_TAG


#  Update the output.json with ECR HELM CHART & DOCKER Image TAG.


cat > $CODEBUILD_SRC_DIR/output.json << EOF
{
  "imageTag": "$IMAGE_TAG" 
}
EOF

cat $CODEBUILD_SRC_DIR/output.json
