#!/bin/bash
echo "Start Code Scan"

Name=`date +%s`
echo $Name
CODEREVIEW=$(aws codeguru-reviewer create-code-review --region $AWS_REGION --name $Name --repository-association-arn $AWS_CODE_REVIEWER --type '{"RepositoryAnalysis":{"RepositoryHead":{"BranchName":"master"}}}')
codeReviewArn=$(echo $CODEREVIEW | jq -r '.CodeReview.CodeReviewArn')
reviewStatus=''
stat="Pending";
iteration=30
cnt=1
while [ "$stat" != "Completed" ]; do
    if [ $stat = "Failed" ] || [ $stat = "Deleting" ]; then
            echo "The code review failed.";
            exit 1;
    fi
    if [ "$cnt" -gt $iteration ]; then
      echo ""$cnt" -gt $iteration "
      break
    fi
 
    reviewStatus=$(aws codeguru-reviewer describe-code-review --region $AWS_REGION --code-review-arn $codeReviewArn)
    stat=$(echo $reviewStatus | jq -r '.CodeReview.State');
    echo "Code Scan Inprogress"
    let "cnt+=1"
    sleep 30;
done
echo $reviewStatus
if [ "$stat" = "Completed" ]; then 
    echo "Code Scan Completed"
    findingCount=$(echo $reviewStatus | jq -r '.CodeReview.Metrics.FindingsCount')
    echo $findingCount
    if [ "$findingCount" > 0 ];then 
        aws codeguru-reviewer list-recommendations --region $AWS_REGION --code-review-arn $codeReviewArn
    fi 
else 
    echo "The code review failed.";
    exit 1;
fi

