import * as cdk from '@aws-cdk/core';
import * as codecommit from '@aws-cdk/aws-codecommit';
import * as ecr from '@aws-cdk/aws-ecr';
import * as sns from '@aws-cdk/aws-sns';
import * as subs from '@aws-cdk/aws-sns-subscriptions';
import * as ca  from '@aws-cdk/aws-codeartifact';
import * as codeGuru from '@aws-cdk/aws-codeguruprofiler';
import * as pipeline from '@aws-cdk/aws-codepipeline';
import * as codepipeline_actions from "@aws-cdk/aws-codepipeline-actions";
import { BuildEnvironmentVariable, LinuxBuildImage, BuildSpec } from '@aws-cdk/aws-codebuild';
import * as codebuild from "@aws-cdk/aws-codebuild";
import * as iam from '@aws-cdk/aws-iam';
import YAML = require('yaml');
import { readFileSync } from 'fs';
import { CfnOutput, RemovalPolicy } from '@aws-cdk/core';
import { CfnRepositoryAssociation } from '@aws-cdk/aws-codegurureviewer';
import ec2 = require('@aws-cdk/aws-ec2');
import * as config from './../config/config.json'


export class CdkResourcesStack extends cdk.Stack {
  private codeRepo:codecommit.Repository;
  private ecrHelmTest:ecr.Repository;
  private ecrHelmProd:ecr.Repository;
  private ecrFlashAppTest:ecr.Repository;
  private ecrFlashAppProd:ecr.Repository;
  private albIamRole:iam.Role;
  
  //profileGroup:codeGuru.ProfilingGroup;
  codeReviewer:CfnRepositoryAssociation;
  //artifactDomain:ca.CfnDomain;
  //artifactRepository:ca.CfnRepository;
  topic:sns.Topic;
  eksDevClusterName:string;
  eksProdClusterName:string;
  eksDevMasterRoleArn:string;
  eksProdMasterRoleArn:string;
  
  constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    
    let codecommitRepoName="MicroserviceWorkshop"; //Replace the name here May be we will Read from Parameter
    let senderEmail=config.userEmail; // Replace the name here may be we will read from the parameter
    this.eksDevClusterName=config.eksDevClusterName
    this.eksProdClusterName=config.eksProdClusterName
    this.eksDevMasterRoleArn=config.eksDevMasterRoleArn
    this.eksProdMasterRoleArn=config.eksProdMasterRoleArn
   
  
    this.createRepository(codecommitRepoName);
    this.ecrHelmTest=this.createECR("ecr-test");
    this.ecrHelmProd=this.createECR("ecr-prod");
    this.ecrFlashAppTest=this.createECR("flask-app");
    this.ecrFlashAppProd=this.createECR("flask-app-prod");
    this.createSNSTopic("LabTopic",senderEmail);
    this.createALBIamRole()
    this.createCloudGuruReviewer();
    this.createPipeline(codecommitRepoName,this.createCodeBuildIamRole("Workshop-reinvent-role"));
    this.pushToCDKOutput()
    // The code that defines your stack goes here
  }
  
  pushToCDKOutput(){
   new CfnOutput(this,"CodeCommitRepo",{ value: this.codeRepo.repositoryCloneUrlHttp})
   new CfnOutput(this,"testFlaskEcr",{ value: this.ecrFlashAppTest.repositoryUri})
   new CfnOutput(this,"testHelmEcr",{ value: this.ecrHelmTest.repositoryUri})
   new CfnOutput(this,"prodFlaskECR",{ value: this.ecrFlashAppProd.repositoryUri})
   new CfnOutput(this,"prodHelmECR",{ value: this.ecrHelmProd.repositoryUri})
   new CfnOutput(this,"albRole",{ value: this.albIamRole.roleArn})
  }

  createRepository(repositoryName:string){
    
    this.codeRepo = new codecommit.Repository(this, 'Repository' ,{
    repositoryName:repositoryName,
    description: 'Application Repository', // optional property
  
    });
    
  }
  

  createCloudGuruReviewer(){
 
   
  const repositoryAssociation=new CfnRepositoryAssociation(this,"proassociation",{
    name:this.codeRepo.repositoryName,
    type:"CodeCommit"
   })
   this.codeReviewer=repositoryAssociation;
  }
  
  createALBIamRole(){
     const federatedPrincipal = new iam.FederatedPrincipal(
        config.eksOIDCProvider, {
      }, "sts:AssumeRoleWithWebIdentity")
  
    this.albIamRole=new iam.Role(this, 'ALBRole', {
      assumedBy:federatedPrincipal,
      roleName:"AlbRoleName"
    
    });
    // need to Change later limited policy for teh Best practice
   //this.albIamRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName('AdministratorAccess'))
   this.albIamRole.addToPolicy(new iam.PolicyStatement({
      actions: [
        "ec2:AuthorizeSecurityGroupIngress",
                "ec2:CreateSecurityGroup",
                "ec2:CreateTags",
                "ec2:DeleteTags",
                "ec2:DeleteSecurityGroup",
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeTags",
                "ec2:DescribeVpcs",
                "ec2:ModifyInstanceAttribute",
                "ec2:ModifyNetworkInterfaceAttribute",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:AuthorizeSecurityGroupEgress",
                "ec2:RevokeSecurityGroupEgress",
                "ec2:ModifySecurityGroupRules",
                "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
                "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:CreateTargetGroup",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:DeleteRule",
                "elasticloadbalancing:DeleteTargetGroup",
                "elasticloadbalancing:DeregisterTargets",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:ModifyRule",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:RemoveTags",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:SetWebACL",
                "iam:CreateServiceLinkedRole",
                "iam:GetServerCertificate",
                "iam:ListServerCertificates",
                "cognito-idp:DescribeUserPoolClient",
                "waf-regional:GetWebACLForResource",
                "waf-regional:GetWebACL",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "ec2:DescribeAddresses",
                "ec2:DescribeInstances",
                "kms:GenerateRandom",
                "ec2:DescribeCoipPools",
                "ec2:DescribeInternetGateways",
                "elasticloadbalancing:DescribeLoadBalancers",
                "kms:DescribeCustomKeyStores",
                "kms:DeleteCustomKeyStore",
                "elasticloadbalancing:DescribeListeners",
                "ec2:DescribeNetworkInterfaces",
                "kms:UpdateCustomKeyStore",
                "ec2:DescribeAvailabilityZones",
                "kms:CreateKey",
                "ec2:DescribeAccountAttributes",
                "elasticloadbalancing:DescribeListenerCertificates",
                "sts:AssumeRoleWithWebIdentity",
                "kms:ConnectCustomKeyStore",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeTags",
                "kms:CreateCustomKeyStore",
                "ec2:DescribeSecurityGroups",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "kms:ListKeys",
                "iam:CreateServiceLinkedRole",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "ec2:DescribeVpcs",
                "kms:ListAliases",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTargetGroups",
                "kms:DisconnectCustomKeyStore",
                "elasticloadbalancing:DescribeRules",
                "ec2:DescribeSubnets"
      ],
      resources: ["*"]
    }))


   this.albIamRole.addToPolicy(new iam.PolicyStatement({
      actions: [
        "kms:*"
      ],
      resources: [`arn:aws:kms:*:${this.account}:key/*`,
                `arn:aws:kms:*:${this.account}:alias/*`]
    }))
  }
  
  

  createCodeBuildIamRole(roleName:string){
  // To DO : Add Policy in the Role For Accing ECR Log Group ,EKS Cluster 
  const role=new iam.Role(this, 'Role', {
      roleName: roleName,
      assumedBy: new iam.ServicePrincipal("codebuild.amazonaws.com"),
    
    });

    
    role.addToPolicy(new iam.PolicyStatement({
      actions: [
        "ecr:*",
        "eks:*",
        "sts:*",
        "codeartifact:*",
        "codecommit:BatchGetCommits",
        "codecommit:GitPull",
        "codecommit:ListBranches",
        "codeguru-reviewer:*",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "SNS:Publish"
      ],
      resources: ["*"]
    }))
    return role;
  }
  
  createECR(repositoryName:string){
    
    return new ecr.Repository(this,repositoryName,{
      repositoryName:repositoryName,
      imageScanOnPush:true,
      removalPolicy:RemovalPolicy.DESTROY // THIS SHOULD not be done for the Production Environment 
    })
  }
  
  createSNSTopic(topicName:string,email:string){
    this.topic = new sns.Topic(this, 'Topic', {
    displayName: 'ApplicationPipelineStatus',
    topicName: topicName
    });
    this.topic.addSubscription(new subs.EmailSubscription(email));
  }
  
  createPipeline(pipelineName:string,codebuildRole:iam.Role){
    
 
    let codeRepo=this.codeRepo;
    let sourceArtifact = new pipeline.Artifact();
    let bncOutput=new pipeline.Artifact("Build-Containerize");
    let vndOutput=new pipeline.Artifact("Validate-and-Deploy-to-Test");
    let tnpOutput=new pipeline.Artifact("Test-and-Promote");
    let dtpOutput=new pipeline.Artifact("Deploy-to-Production");
    const appPipeline=new  pipeline.Pipeline(this,"pipeline",{
      pipelineName:pipelineName,
      
      stages:[
          {
            stageName:"Source",
            actions:[
                  new codepipeline_actions.CodeCommitSourceAction({
                    actionName: "App-Source",
                    repository: codeRepo,
                    branch: "master",
                    output: sourceArtifact,
                    codeBuildCloneOutput:true
                  })  
            ]
            
          },{
            
            stageName:"Build-and-Containerize",
            actions:[
              this.addBuildAction("Build-and-Containerize",sourceArtifact,{
                "ECR_DOCKER_REPO":{value:this.ecrFlashAppTest.repositoryName},
                "ECR_HELM_REPO":{value:this.ecrHelmTest.repositoryName},
                //"AWS_CODEGURU_PROFILER_GROUP_NAME":{value:this.profileGroup.profilingGroupName},
                "AWS_CODE_REVIEWER":{value:this.codeReviewer.attrAssociationArn},
                "ACCOUNTID":{value:this.account},
                "AWS_CODEGURU_PROFILER_TARGET_REGION":{value:this.region},
                "EXECUTABLENAME":{value:"Build-and-Containerize.sh"},
                "ARTIFACT_DOMAIN":{value:config.codeArtifactDomain},
                "ARTIFACT_REPOSITORY":{value:config.codeArtifactRepository},
                "SNS_TOPIC":{value:this.topic.topicArn}
              },
              codebuildRole,
              bncOutput)
              ]
          },
          {
            
            stageName:"Validate-and-Deploy-to-Test",
            actions:[
              this.addBuildAction("Validate-and-Deploy-to-Test",bncOutput,{
                "ECR_DOCKER_REPO":{value:this.ecrFlashAppTest.repositoryName},
                "ECR_HELM_REPO":{value:this.ecrHelmTest.repositoryName},
              
                "AWS_CODEGURU_PROFILER_TARGET_REGION":{value:this.region},
              "ARTIFACT_DOMAIN":{value:config.codeArtifactDomain},
                "ARTIFACT_REPOSITORY":{value:config.codeArtifactRepository},
                "ACCOUNTID":{value:this.account},
                "EXECUTABLENAME":{value:"Validate-and-Deploy-to-Test.sh"},
                "EKS_CLUSTERNAME":{value:this.eksDevClusterName},
                "EKS_CLUSTERROLE_ARN":{value:this.eksDevMasterRoleArn},
                "SNS_TOPIC":{value:this.topic.topicArn}
              },
              codebuildRole,
              vndOutput)
              ]
          },
          {
            stageName:"Test-and-Promote",
             actions:[
              this.addBuildAction("Test-and-Promote",vndOutput,{
                "TEST_ECR_DOCKER_REPO":{value:this.ecrFlashAppTest.repositoryName},
                "TEST_ECR_HELM_REPO":{value:this.ecrHelmTest.repositoryName},
                "ECR_DOCKER_REPO":{value:this.ecrFlashAppProd.repositoryName},
                "ECR_HELM_REPO":{value:this.ecrHelmProd.repositoryName},
                "AWS_CODEGURU_PROFILER_TARGET_REGION":{value:this.region},
                "ACCOUNTID":{value:this.account},
                "EXECUTABLENAME":{value:"Test-and-Promote.sh"},
                "ARTIFACT_DOMAIN":{value:config.codeArtifactDomain},
                "ARTIFACT_REPOSITORY":{value:config.codeArtifactRepository},
                "SNS_TOPIC":{value:this.topic.topicArn}
              },codebuildRole,
              tnpOutput,"BuildVariables")
              ]
            
          },
          {
            stageName:"Approval",
            actions:[
              new codepipeline_actions.ManualApprovalAction({
                actionName:"Approval",
                notificationTopic:this.topic,
                externalEntityLink:"#{BuildVariables.SERVICE_URL_OUT}"
              })
            ]
          },
          {
             stageName:"Deploy-to-Production",
             actions:[
              this.addBuildAction("Deploy-to-Production",tnpOutput,{
                "ECR_HELM_REPO":{value:this.ecrHelmProd.repositoryName},
                "ECR_DOCKER_REPO":{value:this.ecrFlashAppProd.repositoryName},
             
                "AWS_CODEGURU_PROFILER_TARGET_REGION":{value:this.region},
                "ARTIFACT_DOMAIN":{value:config.codeArtifactDomain},
                "ARTIFACT_REPOSITORY":{value:config.codeArtifactRepository},
                "ACCOUNTID":{value:this.account},
                "EXECUTABLENAME":{value:"Deploy-to-Production.sh"},
                "EKS_CLUSTERNAME":{value:this.eksProdClusterName},
                "EKS_CLUSTERROLE_ARN":{value:this.eksProdMasterRoleArn},
                "SNS_TOPIC":{value:this.topic.topicArn}
              },
              codebuildRole,
              dtpOutput)
              ]
          }
        ]
    });
  
    new CfnOutput(this,"codePipeline",{ value: appPipeline.pipelineName})
    
    
    // Add Policy to 
   // appPipeline.addToRolePolicy(new )
  }
  
  
  addBuildAction(buildProjectName:string,sourceArtifact:pipeline.Artifact,environmentvariables:{ [name: string]: BuildEnvironmentVariable;},cbRole:iam.Role,outputArtifact?:pipeline.Artifact,variableNameSpace?:string){
   
    let buildspecContent = YAML.parse(readFileSync(`${__dirname}/buildSpec/buildSpec-application.yaml`, "utf8"));
   
    const cbProject=new codebuild.PipelineProject(this,buildProjectName,{
      environmentVariables:environmentvariables,
      environment:{ buildImage:LinuxBuildImage.STANDARD_5_0,
      privileged:true
      },
      projectName:buildProjectName,
      buildSpec:BuildSpec.fromObjectToYaml(buildspecContent),
      role:cbRole
    });
    return new codepipeline_actions.CodeBuildAction({
      actionName:buildProjectName,
      input:sourceArtifact,
      outputs: outputArtifact!=undefined?[outputArtifact]:undefined,
      project:cbProject,
      variablesNamespace:variableNameSpace
    });
  }
 
  
}
