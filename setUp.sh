#!/bin/bash

sudo yum install -y jq

USER_EMAIL="participant@workshops.aws"
export AWS_REGION=`curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
EKS_STACK_NAME="eksctl-eksworkshop-eksctl-cluster"

aws configure set region $AWS_REGION
ACCOUNTID=$(aws sts get-caller-identity | jq -r ".Account")

cd aws-prerequisite
npm install
stackName=$(cdk ls)
echo $stackName
cdk deploy --require-approval never
cd ../

# Install and configure kubectl
sudo curl --silent --location -o /usr/local/bin/kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.19.6/2021-01-05/bin/linux/amd64/kubectl
sudo chmod +x /usr/local/bin/kubectl
aws eks update-kubeconfig --region $AWS_REGION --name eksworkshop-eksctl

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Install helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh


aws cloudformation  describe-stacks --stack-name $stackName 

ARTIFACT_DOMAIN=$(aws cloudformation --region $AWS_REGION describe-stacks --stack-name $stackName --query "Stacks[0].Outputs[?OutputKey=='domainName'].OutputValue" --output text)
echo $ARTIFACT_DOMAIN
ARTIFACT_REPOSITORY=$(aws cloudformation --region $AWS_REGION describe-stacks --stack-name $stackName --query "Stacks[0].Outputs[?OutputKey=='repositoryName'].OutputValue" --output text)
echo $ARTIFACT_REPOSITORY

aws codeartifact login --tool npm --repository $ARTIFACT_REPOSITORY --domain $ARTIFACT_DOMAIN --domain-owner $ACCOUNTID

EKS_CLUSTER=$(aws cloudformation --region $AWS_REGION describe-stacks --stack-name $EKS_STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='ARN'].OutputValue" --output text)
EKS_CLUSTER=$(echo $EKS_CLUSTER |cut -d '/' -f 2)
echo $EKS_CLUSTER
 

OIDC_PROVIDER=$(aws eks describe-cluster --name $EKS_CLUSTER --query "cluster.identity.oidc.issuer" --output text)
OIDC_PROVIDER=$(echo $OIDC_PROVIDER| cut -d '/' -f 5)

eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER --approve

cd cdk-resources
cat >config/config.json << EOF
{
    "userEmail":"$USER_EMAIL",
    "eksDevClusterName":"$EKS_CLUSTER",
    "eksProdClusterName":"$EKS_CLUSTER",
    "eksOIDCProvider":"arn:aws:iam::$ACCOUNTID:oidc-provider/oidc.eks.$AWS_REGION.amazonaws.com/id/$OIDC_PROVIDER",
    "codeArtifactDomain":"$ARTIFACT_DOMAIN",
    "codeArtifactRepository":"$ARTIFACT_REPOSITORY",
    "eksDevMasterRoleArn":"arn:aws:iam::$ACCOUNTID:role/eksworkshop-admin",
    "eksProdMasterRoleArn":"arn:aws:iam::$ACCOUNTID:role/eksworkshop-admin"
}
EOF



npm install
stackName=$(cdk ls)
echo $stackName
cdk bootstrap aws://$ACCOUNTID/$AWS_REGION
cdk deploy --require-approval never
cd ../
ALB_ROLE=$(aws cloudformation --region $AWS_REGION describe-stacks --stack-name $stackName --query "Stacks[0].Outputs[?OutputKey=='albRole'].OutputValue" --output text)
CODE_COMMIT=$(aws cloudformation --region $AWS_REGION describe-stacks --stack-name $stackName --query "Stacks[0].Outputs[?OutputKey=='CodeCommitRepo'].OutputValue" --output text)

echo $ALB_ROLE
echo $CODE_COMMIT


cd application/helm-charts
helm upgrade --install loadbalancer -n kube-system aws-load-balancer-controller \
  --set clusterName=$EKS_CLUSTER \
  --set serviceAccount.create=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_ROLE \
  --set serviceAccount.name=aws-load-balancer-controller 
cd ../../

cd application
git init 
git remote add origin $CODE_COMMIT
git add .
git commit -m "Initial commit"
git push -u origin master
